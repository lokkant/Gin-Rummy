-- Connect menu scene (client): a text field for "host:port" with validation, ENTER starts the game scene
-- (SceneManager.switch("game", address)), a BACK button to the start menu and an ENTER button that does the
-- same as the ENTER key. It is reached
-- from the start menu ("Join a game") and when a joined game is left. `require "main"` returns the
-- SceneManager.

local love = require "love"
local SceneManager = require "main"
local ui = require "ui"
local felt = require "client/felt"
local server_config = require "server_config"

local Scene = {}

local font
local label_font

-- State of the text field: current text, size in pixels and the error shown under it (nil = none).
local form = {
    text = "",
    width = 400,
    height = 50,
    error = nil
}

local BUTTON_WIDTH = 200
local BUTTON_HEIGHT = 50
local BUTTON_GAP = 20

local GREEN = {0.3, 0.6, 0.3, 1}
local GRAY = {0.3, 0.3, 0.3, 1}

-- Returns the rects of the BACK and ENTER buttons: side by side below the text field.
local function get_buttons()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local field_y = h / 2 - form.height / 2
    local y = field_y + form.height + 70
    local x = w / 2 - (BUTTON_WIDTH * 2 + BUTTON_GAP) / 2

    return {
        back = {x = x, y = y, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        enter = {x = x + BUTTON_WIDTH + BUTTON_GAP, y = y, w = BUTTON_WIDTH, h = BUTTON_HEIGHT}
    }
end

-- Ctrl+Backspace: removes the trailing non-alphanumeric characters and then the word before them.
local function delete_last_word(text)
    text = string.gsub(text, "[^%w]*$", "")
    text = string.gsub(text, "%w*$", "")
    return text
end

-- Checks the syntax "host:port". Returns true, nil or false, "message". The host may contain letters,
-- digits, dots and dashes; the port must be 1-65535; a host written like an IPv4 address needs four parts
-- of 0-255. Names are not resolved here.
local function validate_address(text)
    if text == "" then
        return false, "Enter an address"
    end

    local host_part, port_part = string.match(text, "^([%w%.%-]+):(%d+)$")

    if host_part == nil then
        return false, "Format must be host:port (e.g. 127.0.0.1:6789)"
    end

    local port = tonumber(port_part)
    if port == nil or port < 1 or port > 65535 then
        return false, "Port must be a number between 1 and 65535"
    end

    local o1, o2, o3, o4 = string.match(host_part, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if o1 ~= nil then
        for _, octet in ipairs({o1, o2, o3, o4}) do
            local n = tonumber(octet)
            if n == nil or n < 0 or n > 255 then
                return false, "Invalid IP address"
            end
        end
    end

    return true, nil
end

-- Scene entry: enables text input events, loads the fonts and clears the field.
function Scene.load()
    love.keyboard.setTextInput(true)
    server_config.reset()

    if font == nil then
        font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28)
        label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 22)
    end

    form.text = ""
    form.error = nil
end

-- Appends typed text (line breaks removed) to the field.
function Scene.textinput(t)
    t = string.gsub(t, "[\r\n]", "")
    if t == "" then return end

    form.text = form.text .. t
    form.error = nil
end

-- Validates the typed address: starts the game scene when it is fine, otherwise shows the error under the
-- field.
local function connect()
    local ok, error_message = validate_address(form.text)

    if ok then
        SceneManager.switch("game", form.text)
    else
        form.error = error_message
    end
end

-- Backspace (with Ctrl: a whole word), Ctrl+V paste, ENTER validates the address and starts the game
-- scene or shows the error.
function Scene.keypressed(key)
    local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")

    if key == "backspace" then
        if ctrl_down then
            form.text = delete_last_word(form.text)
        else
            form.text = string.sub(form.text, 1, #form.text - 1)
        end
        form.error = nil
    elseif key == "v" and ctrl_down then
        local clipboard_text = love.system.getClipboardText()
        if clipboard_text ~= nil then
            clipboard_text = string.gsub(clipboard_text, "[\r\n]", "")
            form.text = form.text .. clipboard_text
            form.error = nil
        end
    elseif key == "return" or key == "kpenter" then
        connect()
    end
end

-- A left click on BACK returns to the start menu, a click on ENTER connects like the ENTER key.
function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    local buttons = get_buttons()

    if ui.point_in_rect(x, y, buttons.back) then
        SceneManager.switch("start")
    elseif ui.point_in_rect(x, y, buttons.enter) then
        connect()
    end
end

-- Draws the form: the plain table, label, text field, error message and the BACK and ENTER buttons.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    felt.draw_plain()

    local field_x = w / 2 - form.width / 2
    local field_y = h / 2 - form.height / 2

    love.graphics.setFont(label_font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("Type IP and press Enter:", 0, field_y - 45, w, "center")

    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", field_x, field_y, form.width, form.height)

    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.rectangle("line", field_x, field_y, form.width, form.height)

    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(form.text, field_x, field_y + form.height / 2 - font:getHeight() / 2, form.width, "center")

    if form.error ~= nil then
        love.graphics.setFont(label_font)
        love.graphics.setColor(0.9, 0.3, 0.3)
        love.graphics.printf(form.error, 0, field_y + form.height + 20, w, "center")
    end

    local buttons = get_buttons()

    love.graphics.setFont(label_font)
    ui.draw_button(buttons.back, "BACK", GRAY)
    ui.draw_button(buttons.enter, "ENTER", GREEN)

    love.graphics.setColor(1, 1, 1)
end

return Scene
