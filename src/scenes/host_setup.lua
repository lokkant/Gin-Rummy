-- The "Host a game" screen (client): the host picks the port, optionally loads a settings file (see
-- server_config.lua; a file can also be dropped onto the window), sets how many seconds each phase of a turn
-- lasts and switches the horror mode on or off. START SERVER then starts the game server inside this program
-- with those settings and enters the room as a normal player; the game scene shows the address the other
-- player must use. The detailed settings are made in scenes/config_editor.lua.

local love = require "love"
local server = require "server"
local host_info = require "host_info"
local server_config = require "server_config"
local ui = require "ui"
local form = require "client/form"
local felt = require "client/felt"

local Scene = {}

local DEFAULT_PORT = 6789
local DEFAULT_FILE = "(default settings)"

local FORM_WIDTH = 640
local BUTTON_WIDTH = 260
local BUTTON_HEIGHT = 50

local GREEN = {0.3, 0.6, 0.3, 1}
local GRAY = {0.3, 0.3, 0.3, 1}

-- The settings the quick form shows (the phase times and the horror switch); everything else comes from the
-- chosen file.
local QUICK_KEYS = {"idle_warning_start", "idle_warning_full_delay", "idle_crack_delay", "idle_loss_delay",
                    "horror_enabled"}

local title_font
local label_font
local field_font
local hint_font

local settings_form
-- The values of the chosen file (clean), the message under the buttons and the typed port, which is kept
-- between visits.
local file_values = {}
local message
local message_is_error = false
local port_text = tostring(DEFAULT_PORT)

-- Returns the list of choices of the file row: the default settings and every file in the save folder.
local function get_file_options()
    local options = {DEFAULT_FILE}

    for _, name in ipairs(server_config.list_files()) do
        table.insert(options, name)
    end

    return options
end

-- Returns the schema entry of a key.
local function get_entry(key)
    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.key == key then return entry end
    end
end

-- Fills the phase fields and the horror switch from the host's own settings with the chosen file over them.
local function show_file_values()
    local values = server_config.base_values(file_values)

    for _, key in ipairs(QUICK_KEYS) do
        form.set_value(settings_form, key, values[key])
    end
end

-- Called when the file choice changes: reads the file (the default settings for the first option) and shows
-- its values.
local function on_file_chosen(row)
    local name = row.options[row.index]
    message = nil

    if row.index == 1 then
        file_values = {}
    else
        local values, problem = server_config.read(name)

        if values == nil then
            file_values = {}
            message, message_is_error = problem, true
        else
            file_values = values
        end
    end

    show_file_values()
end

-- Builds the rows of the form.
local function build_rows()
    local rows = {
        {kind = "number", key = "port", label = "Port", text = port_text, min = 1, max = 65535,
         integer = true},
        {kind = "choice", key = "file", label = "Settings file", options = get_file_options(), index = 1,
         on_change = on_file_chosen},
        {kind = "header", label = "Time for each phase of a turn (seconds)"}
    }

    for _, key in ipairs(QUICK_KEYS) do
        local entry = get_entry(key)

        if entry.kind == "number" then
            table.insert(rows, {kind = "number", key = key, label = entry.label, text = "", min = entry.min,
                                max = entry.max, integer = entry.integer})
        end
    end

    table.insert(rows, {kind = "header", label = "Horror mode"})
    table.insert(rows, {kind = "bool", key = "horror_enabled", label = "Unsettling effects for both players",
                        value = true})

    return rows
end

-- Returns the rectangles of the form and of the START SERVER, EDIT ALL SETTINGS and BACK buttons.
local function get_layout()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local form_height = #settings_form.rows * form.ROW_HEIGHT
    local top = math.max(90, h / 2 - (form_height + 2 * (BUTTON_HEIGHT + 14)) / 2 - 20)
    local buttons_y = top + form_height + 20
    local second_row_y = buttons_y + BUTTON_HEIGHT + 14

    return {
        form = {x = w / 2 - FORM_WIDTH / 2, y = top, w = FORM_WIDTH, h = form_height},
        start = {x = w / 2 - BUTTON_WIDTH / 2, y = buttons_y, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        edit = {x = w / 2 - BUTTON_WIDTH - 7, y = second_row_y, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        back = {x = w / 2 + 7, y = second_row_y, w = BUTTON_WIDTH, h = BUTTON_HEIGHT}
    }
end

-- Scene entry: fonts are made once, the settings of an earlier game are put back and the form is built.
function Scene.load()
    love.keyboard.setTextInput(true)
    server_config.reset()

    if field_font == nil then
        title_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 48)
        label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 18)
        field_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 20)
        hint_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 15)
    end

    file_values = {}
    message = nil
    settings_form = form.new(build_rows(), {label = label_font, field = field_font})
    show_file_values()
    form.set_area(settings_form, get_layout().form)
end

-- Re-lays the form out after the window changed size.
function Scene.resize()
    form.set_area(settings_form, get_layout().form)
end

-- Applies the chosen settings and starts the server on the typed port, then enters the room. A bad number,
-- or a port that can't be used, stays on this screen as a message.
local function start_server()
    local values, problem = form.read_values(settings_form)

    if values == nil then
        message, message_is_error = problem, true
        return
    end

    port_text = tostring(values.port)

    local settings = {}
    for _, key in ipairs(QUICK_KEYS) do
        settings[key] = values[key]
    end

    server_config.reset()
    server_config.apply(file_values)
    server_config.apply(server_config.sanitize(settings))

    local started, start_problem = server.start(values.port)

    if not started then
        server_config.reset()
        message, message_is_error = start_problem, true
        return
    end

    SceneManager.switch("game", "127.0.0.1:" .. values.port, {
        hosting = true,
        addresses = host_info.get_addresses(values.port)
    })
end

-- A settings file dropped onto the window is copied into the save folder and chosen.
function Scene.filedropped(file)
    local path = file:getFilename()
    local opened = file:open("r")
    local text = opened and file:read() or nil
    file:close()

    if text == nil then
        message, message_is_error = "The dropped file could not be read", true
        return
    end

    local name, problem = server_config.import(path, text)

    if name == nil then
        message, message_is_error = problem, true
        return
    end

    local row = form.find_row(settings_form, "file")
    row.options = get_file_options()

    for index, option in ipairs(row.options) do
        if option == name then row.index = index end
    end

    on_file_chosen(row)
    message, message_is_error = "Loaded " .. name, false
end

-- Typed text goes to the focused field.
function Scene.textinput(t)
    form.textinput(settings_form, t)
end

-- Escape goes back; Enter on a field moves on, and starts the server when no field has the focus.
function Scene.keypressed(key)
    if key == "escape" then
        SceneManager.switch("start")
    elseif form.keypressed(settings_form, key) then
        return
    elseif key == "return" or key == "kpenter" then
        start_server()
    end
end

-- The mouse wheel scrolls the form (it only moves when the window is too small for all rows).
function Scene.wheelmoved(dx, dy)
    form.wheelmoved(settings_form, dy)
end

-- The form takes the clicks on its rows; the three buttons start the server, open the detailed editor or go
-- back.
function Scene.mousepressed(x, y, button)
    if form.mousepressed(settings_form, x, y, button) or button ~= 1 then return end

    local rects = get_layout()

    if ui.point_in_rect(x, y, rects.start) then
        start_server()
    elseif ui.point_in_rect(x, y, rects.edit) then
        SceneManager.switch("config", "host")
    elseif ui.point_in_rect(x, y, rects.back) then
        SceneManager.switch("start")
    end
end

-- Draws the table, the title, the form, the buttons, the message and the hints.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local rects = get_layout()

    felt.draw_plain()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(title_font)
    love.graphics.printf("HOST A GAME", 0, math.max(10, rects.form.y - 75), w, "center")

    form.draw(settings_form)

    love.graphics.setFont(label_font)
    ui.draw_button(rects.start, "START SERVER", GREEN)
    ui.draw_button(rects.edit, "ALL SETTINGS...", GRAY)
    ui.draw_button(rects.back, "BACK", GRAY)

    local text_y = rects.back.y + rects.back.h + 16
    if message then
        love.graphics.setFont(hint_font)
        love.graphics.setColor(message_is_error and {0.9, 0.3, 0.3} or {0.8, 1, 0.8})
        love.graphics.printf(message, w * 0.15, text_y, w * 0.7, "center")
        text_y = text_y + 24
    end

    love.graphics.setFont(hint_font)
    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Drop a settings file onto the window to use it. ALL SETTINGS... makes one.\n" ..
                         "Files live in " .. server_config.get_folder_path(),
                         w * 0.1, text_y, w * 0.8, "center")

    love.graphics.setColor(1, 1, 1, 1)
end

return Scene
