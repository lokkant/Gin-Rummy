-- The first screen (client): the player chooses to join somebody's game ("menu", scenes/connect_menu.lua) or
-- to host one. Hosting starts the game server inside this program on the chosen port and enters the room at
-- once as a normal player; the game scene then shows the address the other player must use.

local love = require "love"
local server = require "server"
local host_info = require "host_info"
local ui = require "ui"

local Scene = {}

local DEFAULT_PORT = "6789"
local MAX_PORT_DIGITS = 5

local BUTTON_WIDTH = 360
local BUTTON_HEIGHT = 60
local FIELD_WIDTH = 160
local ROW_SPACING = 90

local GREEN = {0.3, 0.6, 0.3, 1}
local BLUE = {0.25, 0.4, 0.65, 1}
local DARK_RED = {0.6, 0.2, 0.2, 1}

local title_font
local font
local label_font

-- The port text field and the message shown under the buttons (nil when there is none).
local port_text = DEFAULT_PORT
local error_message

-- Returns the rectangles of the three buttons and of the port field for the current window size. The block
-- is centred; the "host" row holds the port field to the left of its button.
local function get_layout()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local top = h / 2 - ROW_SPACING

    local host_row_width = FIELD_WIDTH + 20 + BUTTON_WIDTH
    local host_row_x = w / 2 - host_row_width / 2

    return {
        join = {x = w / 2 - BUTTON_WIDTH / 2, y = top, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        port = {x = host_row_x, y = top + ROW_SPACING, w = FIELD_WIDTH, h = BUTTON_HEIGHT},
        host = {x = host_row_x + FIELD_WIDTH + 20, y = top + ROW_SPACING, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        quit = {x = w / 2 - BUTTON_WIDTH / 2, y = top + ROW_SPACING * 2.2, w = BUTTON_WIDTH, h = BUTTON_HEIGHT}
    }
end

-- Scene entry: fonts are made once; the port field keeps its text between visits, the old error goes away.
function Scene.load()
    love.keyboard.setTextInput(true)

    if font == nil then
        title_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 64)
        font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28)
        label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 22)
    end

    error_message = nil
end

-- Returns the port the player typed as a number, or nil and a message when it is not a valid port.
local function read_port()
    local port = tonumber(port_text)

    if port == nil or port < 1 or port > 65535 then
        return nil, "The port must be a number between 1 and 65535"
    end

    return port
end

-- Starts the server on the typed port and enters the room as a player. The game scene gets the addresses
-- to show to the other player. If the port can't be used the reason stays on this screen.
local function host_game()
    local port, problem = read_port()

    if port == nil then
        error_message = problem
        return
    end

    local started, start_problem = server.start(port)

    if not started then
        error_message = start_problem
        return
    end

    SceneManager.switch("game", "127.0.0.1:" .. port, {
        hosting = true,
        addresses = host_info.get_addresses(port)
    })
end

-- Only digits go into the port field.
function Scene.textinput(t)
    local digits = string.gsub(t, "%D", "")

    if digits == "" or #port_text + #digits > MAX_PORT_DIGITS then return end

    port_text = port_text .. digits
    error_message = nil
end

-- Backspace edits the port (Ctrl+Backspace clears it), Ctrl+V pastes the digits of the clipboard, Enter
-- hosts.
function Scene.keypressed(key)
    local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")

    if key == "backspace" then
        if ctrl_down then
            port_text = ""
        else
            port_text = string.sub(port_text, 1, #port_text - 1)
        end
        error_message = nil
    elseif key == "v" and ctrl_down then
        Scene.textinput(love.system.getClipboardText() or "")
    elseif key == "return" or key == "kpenter" then
        host_game()
    end
end

-- The three buttons: join (to the address screen), host, quit.
function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    local rects = get_layout()

    if ui.point_in_rect(x, y, rects.join) then
        SceneManager.switch("menu")
    elseif ui.point_in_rect(x, y, rects.host) then
        host_game()
    elseif ui.point_in_rect(x, y, rects.quit) then
        love.event.quit()
    end
end

-- Draws the title, the buttons, the port field and the error message, if any.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local rects = get_layout()

    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))
    love.graphics.rectangle("fill", 0, 0, w, h)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(title_font)
    love.graphics.printf("GIN RUMMY", 0, h / 2 - ROW_SPACING - 140, w, "center")

    love.graphics.setFont(font)
    ui.draw_button(rects.join, "JOIN A GAME", BLUE)
    ui.draw_button(rects.host, "HOST A GAME", GREEN)
    ui.draw_button(rects.quit, "QUIT", DARK_RED)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(label_font)
    love.graphics.printf("Port:", rects.port.x, rects.port.y - 28, rects.port.w, "center")

    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", rects.port.x, rects.port.y, rects.port.w, rects.port.h)
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.rectangle("line", rects.port.x, rects.port.y, rects.port.w, rects.port.h)

    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.printf(port_text, rects.port.x, rects.port.y + rects.port.h / 2 - font:getHeight() / 2,
                         rects.port.w, "center")

    if error_message ~= nil then
        love.graphics.setFont(label_font)
        love.graphics.setColor(0.9, 0.3, 0.3)
        love.graphics.printf(error_message, 0, rects.quit.y + rects.quit.h + 25, w, "center")
    end

    love.graphics.setColor(1, 1, 1)
end

return Scene
