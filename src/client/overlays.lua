-- Everything drawn on top of the table - connection messages, pause menu, round result banner, "waiting for
-- layoff" banner, game over screen with the rematch buttons and the "back to menu" button - and the click
-- handling for them. What is shown depends only on state fields (is_paused, is_game_over, round_result,
-- ...) and network.get_status(). A rect is {x, y, w, h} in window pixels.

local love = require "love"
local network = require "network"
local ui = require "ui"

local overlays = {}

-- Button sizes in pixels.
local REMATCH_BUTTON_WIDTH = 140
local REMATCH_BUTTON_HEIGHT = 50
local PAUSE_BUTTON_WIDTH = 260
local PAUSE_BUTTON_HEIGHT = 50
local BACK_BUTTON_WIDTH = 260
local BACK_BUTTON_HEIGHT = 50

-- Button colours, RGBA.
local GREEN = {0.3, 0.6, 0.3, 1}
local RED = {0.6, 0.3, 0.3, 1}
local DARK_RED = {0.6, 0.2, 0.2, 1}
local GRAY = {0.3, 0.3, 0.3, 1}

-- Returns {yes = rect, no = rect}: two buttons side by side, centred just below the middle of the screen.
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

-- Returns {fullscreen, wobble, quit} rects: three buttons stacked around the middle of the screen.
local function get_pause_buttons()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local spacing = 20
    local row = PAUSE_BUTTON_HEIGHT + spacing
    local start_y = h / 2 - 10 - row
    local x = w / 2 - PAUSE_BUTTON_WIDTH / 2

    return {
        fullscreen = {x = x, y = start_y, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT},
        wobble = {x = x, y = start_y + row, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT},
        quit = {x = x, y = start_y + row * 2, w = PAUSE_BUTTON_WIDTH, h = PAUSE_BUTTON_HEIGHT}
    }
end

-- Returns the rect of the "BACK TO MENU" button, below the middle of the screen.
local function get_back_button()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    return {x = w / 2 - BACK_BUTTON_WIDTH / 2, y = h / 2 + 120, w = BACK_BUTTON_WIDTH, h = BACK_BUTTON_HEIGHT}
end

-- True when the rematch question needs no answer any more: we answered, the opponent left or the
-- connection is gone.
local function is_rematch_resolved(state)
    return state.rematch_response_sent or state.opponent_left or network.get_status() == "disconnected" or
           (state.game_over_info ~= nil and state.game_over_info.opponent_disconnected)
end

-- Text of the "no game right now" overlay (connecting, failed, lost, waiting for the second player), nil
-- when the table should be shown normally.
function overlays.get_connection_message(state)
    local status = network.get_status()

    if status == "failed" then
        return "Could not connect to " .. state.server_address
    elseif status == "disconnected" and state.game_over_info == nil then
        return "Connection to the server was lost"
    elseif status == "connecting" then
        return "Connecting to " .. state.server_address .. "..."
    elseif status == "connected" and not state.has_started_first_game then
        return "Waiting for another player..."
    end

    return nil
end

-- "Back to menu" is offered when there is no game to continue (or the server is gone)
function overlays.is_back_button_visible(state)
    if overlays.get_connection_message(state) ~= nil then return true end
    return state.is_game_over and network.get_status() == "disconnected"
end

-- A full-screen overlay (pause, game over, no connection) covers the table, which must then not react to
-- the mouse.
function overlays.covers_table(state)
    return state.is_paused or state.is_game_over or overlays.get_connection_message(state) ~= nil
end

-- Returns (consumed, action): whether an overlay took the click and which action it asks for:
-- "leave", "rematch_yes", "rematch_no", "toggle_fullscreen", "toggle_wobble", "quit" or nil.
-- Priority: no game / lost connection (back button), then the pause menu, then the game over screen.
function overlays.handle_click(state, x, y, button)
    -- The pause menu has its own buttons, so the back button is only offered outside of it.
    if overlays.is_back_button_visible(state) and not state.is_paused then
        if button == 1 and ui.point_in_rect(x, y, get_back_button()) then
            return true, "leave"
        end
        return true, nil
    end

    -- Paused: every click is swallowed, only left clicks on the buttons do something.
    if state.is_paused then
        if button ~= 1 then return true, nil end

        local buttons = get_pause_buttons()

        if ui.point_in_rect(x, y, buttons.fullscreen) then
            return true, "toggle_fullscreen"
        elseif ui.point_in_rect(x, y, buttons.wobble) then
            return true, "toggle_wobble"
        elseif ui.point_in_rect(x, y, buttons.quit) then
            return true, "quit"
        end

        return true, nil
    end

    -- Game over: clicks are swallowed; only left clicks on YES / NO count, and only while the question is
    -- open.
    if state.is_game_over then
        if button ~= 1 or is_rematch_resolved(state) then return true, nil end

        local buttons = get_rematch_buttons()

        if ui.point_in_rect(x, y, buttons.yes) then
            return true, "rematch_yes"
        elseif ui.point_in_rect(x, y, buttons.no) then
            return true, "rematch_no"
        end

        return true, nil
    end

    return false, nil
end

-- Headline of the round result banner from this player's point of view (draw, gin, undercut or plain
-- knock).
local function get_round_result_title(round_result)
    if round_result.is_draw then
        return "The deck ran out - draw!"
    elseif round_result.is_gin then
        return round_result.you_knocked and "You scored big!" or "Better luck next time"
    elseif round_result.is_undercut then
        return round_result.you_knocked and "Undercut! Opponent scored" or "You undercut the knocker!"
    end

    return round_result.you_knocked and "You knocked!" or "Opponent knocked!"
end

-- Draws the round result: a big gold title above the panel for a gin, then a 520 x 240 panel with the
-- headline, both deadwoods, the laid off points (if any) and the round and total scores.
local function draw_round_result(state)
    local round_result = state.round_result
    local w, h = 520, 240
    local px, py = love.graphics.getWidth() / 2 - w / 2, love.graphics.getHeight() / 2 - h / 2

    if round_result.is_gin then
        love.graphics.setFont(state.fonts.gin)
        love.graphics.setColor(1, 0.85, 0.1, 1)
        love.graphics.printf(
            round_result.you_knocked and "YOU GOT GIN!" or "OPPONENT GOT GIN!",
            0, py - 70, love.graphics.getWidth(), "center")
    end

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", px, py, w, h, 10, 10)

    love.graphics.setFont(state.fonts.round_result)
    love.graphics.setColor(1, 1, 1, 1)

    love.graphics.printf(get_round_result_title(round_result), px, py + 20, w, "center")
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

-- Draws the banner shown to the knocker while the opponent lays off cards.
local function draw_waiting_for_layoff(state)
    local w, h = 380, 100
    local px, py = love.graphics.getWidth() / 2 - w / 2, love.graphics.getHeight() / 2 - h / 2
    local font = state.fonts.base

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", px, py, w, h, 10, 10)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("Waiting for opponent to lay off cards...", px, py + h / 2 - font:getHeight() / 2, w, "center")
end

-- Draws the end screen: a dark veil, YOU WIN / YOU LOSE and then, in this order of priority, why the match
-- is really over (opponent disconnected, connection lost, opponent declined) or the rematch question.
local function draw_game_over(state)
    local info = state.game_over_info
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(state.fonts.number)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(info.you_won and "YOU WIN!" or "YOU LOSE", 0, h / 2 - 100, w, "center")

    if info.opponent_disconnected then
        love.graphics.printf("Opponent disconnected.", 0, h / 2 - 40, w, "center")
        love.graphics.printf("Returning to menu...", 0, h / 2 - 10, w, "center")
    elseif network.get_status() == "disconnected" then
        love.graphics.printf("Disconnected from server.", 0, h / 2 - 40, w, "center")
    elseif state.opponent_left then
        love.graphics.printf("Opponent left the game.", 0, h / 2 - 40, w, "center")
        love.graphics.printf("Returning to menu...", 0, h / 2 - 10, w, "center")
    elseif state.rematch_response_sent then
        love.graphics.printf("Waiting for opponent's response...", 0, h / 2 - 40, w, "center")
    else
        love.graphics.printf("Play again?", 0, h / 2 - 40, w, "center")

        local buttons = get_rematch_buttons()
        ui.draw_button(buttons.yes, "YES", GREEN)
        ui.draw_button(buttons.no, "NO", RED)
    end
end

-- Draws a dark veil with the connection message in the middle.
local function draw_connection(state, message)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(state.fonts.base)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(message, 0, h / 2 - 40, w, "center")
end

-- Draws the pause menu: dark veil, title and the three buttons (the wobble and fullscreen labels show
-- their current state).
local function draw_pause(state)
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setFont(state.fonts.base)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf("PAUSED", 0, h / 2 - 200, w, "center")

    local buttons = get_pause_buttons()

    ui.draw_button(buttons.fullscreen, "Fullscreen: " .. (love.window.getFullscreen() and "ON" or "OFF"), GRAY)
    ui.draw_button(buttons.wobble, "Card wobble: " .. (WOBBLE_ENABLED and "ON" or "OFF"), GRAY)
    ui.draw_button(buttons.quit, "QUIT GAME", DARK_RED)

    love.graphics.printf("Press ESC to resume", 0, buttons.quit.y + buttons.quit.h + 25, w, "center")
end

-- Draws all overlays, later ones on top: round result, waiting banner, end screen, connection message,
-- back button, pause menu.
function overlays.draw(state)
    if state.round_result ~= nil then
        draw_round_result(state)
    end

    if state.waiting_for_layoff then
        draw_waiting_for_layoff(state)
    end

    if state.game_over_info ~= nil then
        draw_game_over(state)
    end

    local connection_message = overlays.get_connection_message(state)
    if connection_message ~= nil then
        draw_connection(state, connection_message)
    end

    if overlays.is_back_button_visible(state) and not state.is_paused then
        love.graphics.setFont(state.fonts.base)
        ui.draw_button(get_back_button(), "BACK TO MENU", DARK_RED)
    end

    if state.is_paused then
        draw_pause(state)
    end
end

return overlays
