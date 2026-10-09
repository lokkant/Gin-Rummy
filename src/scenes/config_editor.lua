-- The "Create server config" screen (client): a scrolling form with every setting of the game (the time of
-- each phase of a turn, the horror mode and its effects, the volume, ...), filled with the host's own values
-- or with an existing settings file. SAVE writes the settings to a file in the save folder
-- (server_config.lua), which can then be chosen on the host screen (scenes/host_setup.lua), dropped onto it,
-- or given to a headless server with `--config`. Nothing is changed in the running game.

local love = require "love"
local server_config = require "server_config"
local ui = require "ui"
local form = require "client/form"
local felt = require "client/felt"

local Scene = {}

local DEFAULT_FILE = "(default settings)"
local DEFAULT_NAME = "my_server"

local FORM_WIDTH = 760
local BUTTON_WIDTH = 220
local BUTTON_HEIGHT = 46
-- Pixels between the form and the bottom buttons and between the title and the form.
local TOP = 90
local BOTTOM = 150

local GREEN = {0.3, 0.6, 0.3, 1}
local GRAY = {0.3, 0.3, 0.3, 1}

local title_font
local label_font
local field_font
local hint_font

local settings_form
-- The file name typed last (kept between visits) and the message under the form.
local name_text = DEFAULT_NAME
local message
local message_is_error = false
-- The scene BACK and Escape return to: "start" (opened from the start menu) or "host".
local return_scene = "start"

-- Returns the list of choices for the starting point: the default settings and every saved file.
local function get_file_options()
    local options = {DEFAULT_FILE}

    for _, name in ipairs(server_config.list_files()) do
        table.insert(options, name)
    end

    return options
end

-- Shows the values of a settings table (a key -> value table) in the form.
local function show_values(values)
    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.key then
            form.set_value(settings_form, entry.key, values[entry.key])
        end
    end
end

-- Called when the starting point changes: the form shows the host's own values with the file over them.
local function on_start_chosen(row)
    message = nil

    if row.index == 1 then
        show_values(server_config.base_values())
        return
    end

    local file_values, problem = server_config.read(row.options[row.index])

    if file_values == nil then
        message, message_is_error = problem, true
        show_values(server_config.base_values())
    else
        show_values(server_config.base_values(file_values))
    end
end

-- Builds the rows: the file name, the starting point and then one row per setting of the schema.
local function build_rows()
    local rows = {
        {kind = "text", key = "name", label = "File name", text = name_text,
         max_length = server_config.MAX_NAME_LENGTH, allowed = "[%w_%-]"},
        {kind = "choice", key = "start", label = "Start from", options = get_file_options(), index = 1,
         on_change = on_start_chosen}
    }

    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.title then
            table.insert(rows, {kind = "header", label = entry.title})
        elseif entry.kind == "bool" then
            table.insert(rows, {kind = "bool", key = entry.key, label = entry.label, value = false})
        else
            table.insert(rows, {kind = "number", key = entry.key, label = entry.label, text = "",
                                min = entry.min, max = entry.max, integer = entry.integer})
        end
    end

    return rows
end

-- Returns the rectangles of the form and of the SAVE and BACK buttons.
local function get_layout()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local form_width = math.min(FORM_WIDTH, w - 80)

    return {
        form = {x = w / 2 - form_width / 2, y = TOP, w = form_width, h = math.max(100, h - TOP - BOTTOM)},
        save = {x = w / 2 - BUTTON_WIDTH - 10, y = h - BOTTOM + 20, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        back = {x = w / 2 + 10, y = h - BOTTOM + 20, w = BUTTON_WIDTH, h = BUTTON_HEIGHT}
    }
end

-- Scene entry: fonts are made once and the form is built with the host's own values. `came_from` is the scene
-- to return to.
function Scene.load(came_from)
    return_scene = came_from or "start"
    love.keyboard.setTextInput(true)
    server_config.reset()

    if field_font == nil then
        title_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 40)
        label_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 17)
        field_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 19)
        hint_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 15)
    end

    message = nil
    settings_form = form.new(build_rows(), {label = label_font, field = field_font})
    show_values(server_config.base_values())
    form.set_area(settings_form, get_layout().form)
end

-- Re-lays the form out after the window changed size.
function Scene.resize()
    form.set_area(settings_form, get_layout().form)
end

-- Saves the settings of the form to the file named in the form; a bad number or name stays as a message.
local function save()
    local values, problem = form.read_values(settings_form)

    if values == nil then
        message, message_is_error = problem, true
        return
    end

    local name = server_config.clean_name(form.get_value(settings_form, "name"))
    if name == nil then
        message, message_is_error = "Type a file name (letters, digits, _ and -)", true
        return
    end

    local ok, result = server_config.save(name, values)

    if not ok then
        message, message_is_error = result, true
        return
    end

    name_text = name
    local row = form.find_row(settings_form, "start")
    row.options = get_file_options()
    message, message_is_error = "Saved as " .. result .. " - choose it when hosting a game", false
end

-- Typed text goes to the focused field.
function Scene.textinput(t)
    form.textinput(settings_form, t)
end

-- Escape goes back.
function Scene.keypressed(key)
    if key == "escape" then
        SceneManager.switch(return_scene)
    elseif not form.keypressed(settings_form, key) and (key == "return" or key == "kpenter") then
        save()
    end
end

-- The mouse wheel scrolls the form.
function Scene.wheelmoved(dx, dy)
    form.wheelmoved(settings_form, dy)
end

-- The form takes the clicks on its rows; SAVE writes the file, BACK returns to where we came from.
function Scene.mousepressed(x, y, button)
    if form.mousepressed(settings_form, x, y, button) or button ~= 1 then return end

    local rects = get_layout()

    if ui.point_in_rect(x, y, rects.save) then
        save()
    elseif ui.point_in_rect(x, y, rects.back) then
        SceneManager.switch(return_scene)
    end
end

-- Draws the table, the title, the form, the buttons and the message.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local rects = get_layout()

    felt.draw_plain()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(title_font)
    love.graphics.printf("CREATE SERVER CONFIG", 0, 20, w, "center")

    form.draw(settings_form)

    love.graphics.setFont(label_font)
    ui.draw_button(rects.save, "SAVE", GREEN)
    ui.draw_button(rects.back, "BACK", GRAY)

    love.graphics.setFont(hint_font)
    local text_y = rects.save.y + rects.save.h + 12
    if message then
        love.graphics.setColor(message_is_error and {0.9, 0.3, 0.3} or {0.8, 1, 0.8})
        love.graphics.printf(message, w * 0.1, text_y, w * 0.8, "center")
        text_y = text_y + 22
    end

    love.graphics.setColor(1, 1, 1, 0.7)
    love.graphics.printf("Saved in " .. server_config.get_folder_path(), w * 0.1, text_y, w * 0.8, "center")
    love.graphics.setColor(1, 1, 1, 1)
end

return Scene
