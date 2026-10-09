-- The first screen (client): the player chooses to join somebody's game ("menu", scenes/connect_menu.lua),
-- to host one ("host", scenes/host_setup.lua: port, settings, then the game server starts inside this
-- program and the player enters the room as a normal player) or to make a server settings file ("config",
-- scenes/config_editor.lua).

local love = require "love"
local server_config = require "server_config"
local ui = require "ui"
local felt = require "client/felt"

local Scene = {}

local BUTTON_WIDTH = 360
local BUTTON_HEIGHT = 60
local ROW_SPACING = 80

local GREEN = {0.3, 0.6, 0.3, 1}
local BLUE = {0.25, 0.4, 0.65, 1}
local GRAY = {0.3, 0.3, 0.3, 1}
local DARK_RED = {0.6, 0.2, 0.2, 1}

local title_font
local font

-- Returns the rectangles of the four buttons for the current window size. The block is centred.
local function get_layout()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local top = h / 2 - ROW_SPACING * 1.3
    local x = w / 2 - BUTTON_WIDTH / 2

    return {
        join = {x = x, y = top, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        host = {x = x, y = top + ROW_SPACING, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        config = {x = x, y = top + ROW_SPACING * 2, w = BUTTON_WIDTH, h = BUTTON_HEIGHT},
        quit = {x = x, y = top + ROW_SPACING * 3.2, w = BUTTON_WIDTH, h = BUTTON_HEIGHT}
    }
end

-- Scene entry: fonts are made once; the settings of an earlier hosted game are put back.
function Scene.load()
    server_config.reset()

    if font == nil then
        title_font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 64)
        font = love.graphics.newFont("ArchivoBlack-Regular.ttf", 24)
    end
end

-- The four buttons: join (to the address screen), host (to the host screen), create a settings file, quit.
function Scene.mousepressed(x, y, button)
    if button ~= 1 then return end

    local rects = get_layout()

    if ui.point_in_rect(x, y, rects.join) then
        SceneManager.switch("menu")
    elseif ui.point_in_rect(x, y, rects.host) then
        SceneManager.switch("host")
    elseif ui.point_in_rect(x, y, rects.config) then
        SceneManager.switch("config", "start")
    elseif ui.point_in_rect(x, y, rects.quit) then
        love.event.quit()
    end
end

-- Draws the title and the buttons.
function Scene.draw()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local rects = get_layout()

    felt.draw_plain()

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(title_font)
    love.graphics.printf("GIN RUMMY", 0, h / 2 - ROW_SPACING * 1.3 - 140, w, "center")

    love.graphics.setFont(font)
    ui.draw_button(rects.join, "JOIN A GAME", BLUE)
    ui.draw_button(rects.host, "HOST A GAME", GREEN)
    ui.draw_button(rects.config, "CREATE SERVER CONFIG", GRAY)
    ui.draw_button(rects.quit, "QUIT", DARK_RED)

    love.graphics.setColor(1, 1, 1)
end

return Scene
