-- Connect menu scene (client): a text field for "host:port" with validation, ENTER starts the game scene
-- (SceneManager.switch("game", address)), and a QUIT button. main.lua currently connects straight to a
-- local server, so this scene is only reached through "back to menu". `require "main"` returns the
-- SceneManager.

local love = require "love"
local SceneManager = require "main"
local ui = require "ui"

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

local QUIT_BUTTON_WIDTH = 200
local QUIT_BUTTON_HEIGHT = 50

-- Returns the rect of the QUIT button, below the text field.
local function get_quit_button()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local field_y = h / 2 - form.height / 2

    return {
        x = w / 2 - QUIT_BUTTON_WIDTH / 2,
        y = field_y + form.height + 70,
        w = QUIT_BUTTON_WIDTH,
        h = QUIT_BUTTON_HEIGHT
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

    font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 28)
    label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 22)

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
        local ok, error_message = validate_address(form.text)

        if ok then
            SceneManager.switch("game", form.text)
        else
            form.error = error_message
        end
    end
end

-- A left click on QUIT exits the game.
function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    if ui.point_in_rect(x, y, get_quit_button()) then
        love.event.quit()
    end
end

-- Nothing to update; the form only reacts to input.
function Scene.update(dt)

end

-- Draws the form: table-coloured background, label, text field, error message and the QUIT button.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(love.math.colorFromBytes(53, 101, 77, 255))

    love.graphics.rectangle(
        "fill",
        0,
        0,
        w,
        h
    )

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

    local quit_button = get_quit_button()

    love.graphics.setColor(0.6, 0.2, 0.2, 1)
    love.graphics.rectangle("fill", quit_button.x, quit_button.y, quit_button.w, quit_button.h, 8, 8)

    love.graphics.setFont(label_font)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf("QUIT", quit_button.x, quit_button.y + quit_button.h / 2 - 11, quit_button.w, "center")

    love.graphics.setColor(1, 1, 1)
end

return Scene
