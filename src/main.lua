-- Entry point of the LOVE game: global UI scale, the SceneManager (scene registry + screen wipe) and the
-- love.* callbacks that forward everything to the current scene. Runs for both the client and the server:
-- `love . --server [--port N]` only starts the game server (server.lua) without any scene; otherwise the
-- client scenes are registered (scenes/*.lua) and the start menu opens. `love . --connect host:port` skips
-- the menus and joins that server at once (a shortcut for development). A scene is a table with
-- load/update/draw and optional input callbacks. A server started by the "Host a game" button runs inside
-- the client and is updated here every frame, whatever scene is active. Returns SceneManager (also a
-- global) so scenes can `require "main"` it.

local love = require "love"
local server = require "server"


-- `scale` (set in update_scale) equals BASE_SCALE in a window of the reference size and follows the window.
local BASE_SCALE = 2.6
local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080

-- Card art is stored at this integer multiple of its logical pixel grid (SCALE in tools/generate_cards.py,
-- the two must match); cards are drawn at scale / ASSET_RESOLUTION_FACTOR.
ASSET_RESOLUTION_FACTOR = 3

-- Recomputes the global `scale` from the window size. The smaller of the width/height ratios is used so the
-- table always fits the window. Does nothing on the server, where the graphics module is disabled
-- (conf.lua).
local function update_scale()
    if not love.graphics then return end
    local w, h = love.graphics.getDimensions()
    scale = BASE_SCALE * math.min(w / REFERENCE_WIDTH, h / REFERENCE_HEIGHT)
end

-- Initial value; love.resize keeps it up to date.
update_scale()

-- Global scene registry: scenes[name] = scene table; current_scene is the name of the active one (or nil).
SceneManager = {}

SceneManager.scenes = {}
SceneManager.current_scene = nil

-- Duration of one half of the wipe (cover or reveal), in seconds.
local TRANSITION_DURATION = 0.5
-- RGB colour of the wipe curtain.
local TRANSITION_COLOR = {0.09, 0.09, 0.11}

-- State of the screen wipe. A dark curtain slides in from the left ("cover"), the real change (scene
-- switch or on_covered callback, set by begin_transition) is made while the screen is fully hidden,
-- then the curtain slides out to the right ("reveal"). Input is ignored while `active` (see love.* below).
local transition = {
    active = false,
    phase = nil,
    timer = 0,
    pending_name = nil,
    pending_args = nil,
    should_load = false
}

-- Easing for the curtain: fast start, slow finish. t and the result are in 0..1.
local function ease_out_cubic(t)
    local f = t - 1
    return f * f * f + 1
end

-- Registers a scene table under `name`; switch/set refer to scenes by this name.
function SceneManager.add(name, scene)
    SceneManager.scenes[name] = scene
end

-- Makes `name` the current scene. If should_load, also calls its load(...) with the arguments in the
-- list `args` (`unpack` is the LuaJIT global).
local function apply_switch(name, args, should_load)
    SceneManager.current_scene = name

    if should_load then
        local new = SceneManager.scenes[name]
        new.load(unpack(args))
    end
end

-- Starts the wipe. When the screen is fully covered either the scene `name` is activated (should_load:
-- call its load(...) with `args`) or, when name is nil, `on_covered` is called instead. Without graphics
-- (server) there is nothing to animate, so the change happens immediately.
local function begin_transition(name, args, should_load, on_covered)
    if not love.graphics then
        if on_covered then
            on_covered()
        else
            apply_switch(name, args, should_load)
        end
        return
    end

    transition.active = true
    transition.phase = "cover"
    transition.timer = 0
    transition.pending_name = name
    transition.pending_args = args
    transition.should_load = should_load
    transition.on_covered = on_covered
end

-- Switches to scene `name` after the wipe and calls its load(...) with the extra arguments.
function SceneManager.switch(name, ...)
    begin_transition(name, {...}, true, nil)
end

-- Switches to an already loaded scene WITHOUT calling load(), so it keeps its state (e.g. back from
-- the layoff scene to the game scene).
function SceneManager.set(name)
    begin_transition(name, {}, false, nil)
end

-- Plays the wipe without changing the scene and runs `on_covered` while the screen is hidden. Used to reset
-- the table between rounds out of the player's sight.
function SceneManager.flash(on_covered)
    begin_transition(nil, nil, false, on_covered)
end

-- Advances the wipe timer by dt and performs the pending change when the "cover" half finishes.
local function update_transition(dt)
    if not transition.active then return end

    transition.timer = transition.timer + dt

    if transition.phase == "cover" then
        -- Fully covered: the change below is invisible to the player.
        if transition.timer >= TRANSITION_DURATION then
            if transition.pending_name ~= nil then
                apply_switch(transition.pending_name, transition.pending_args, transition.should_load)
            elseif transition.on_covered then
                transition.on_covered()
            end

            transition.phase = "reveal"
            transition.timer = 0
        end
    elseif transition.phase == "reveal" then
        if transition.timer >= TRANSITION_DURATION then
            transition.active = false
            transition.phase = nil
            transition.on_covered = nil
        end
    end
end


-- Draws the curtain over the whole window: x goes -w -> 0 while covering and 0 -> w while revealing.
local function draw_transition()
    if not transition.active then return end

    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    local progress = ease_out_cubic(math.min(transition.timer / TRANSITION_DURATION, 1))

    local x
    if transition.phase == "cover" then
        x = -w + progress * w
    else
        x = progress * w
    end

    love.graphics.setColor(TRANSITION_COLOR[1], TRANSITION_COLOR[2], TRANSITION_COLOR[3], 1)
    love.graphics.rectangle("fill", x, 0, w, h)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Returns the value after the command line option `name` (e.g. "--port 6790" -> "6790"), or nil.
local function get_option(arg, name)
    for i, value in ipairs(arg) do
        if value == name then
            return arg[i + 1]
        end
    end
    return nil
end

-- Returns true if the command line has the flag `name`.
local function has_flag(arg, name)
    for _, value in ipairs(arg) do
        if value == name then
            return true
        end
    end
    return false
end

-- Startup: `--server` starts the headless game server and exits with code 1 if the port is taken. Otherwise
-- the client scenes are registered and the start menu (or, with --connect, the game) opens.
function love.load(arg)
    if has_flag(arg, "--server") then
        if not server.start(tonumber(get_option(arg, "--port"))) then
            love.event.quit(1)
        end
        return
    end

    local game_client = require "scenes/game_client"
    local connect_menu = require "scenes/connect_menu"
    local layoff_scene = require "scenes/layoff_scene"
    local start_menu = require "scenes/start_menu"

    SceneManager.add("game", game_client)
    SceneManager.add("menu", connect_menu)
    SceneManager.add("layoff", layoff_scene)
    SceneManager.add("start", start_menu)

    local address = get_option(arg, "--connect")
    if address then
        SceneManager.switch("game", address)
    else
        SceneManager.switch("start")
    end
end

-- Per-frame update: the current scene first, then the wipe.
function love.update(dt)
    if server.is_running() then
        server.update()
    end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.update then
        scene.update(dt)
    end

    update_transition(dt)
end


-- Per-frame draw: the current scene, with the wipe curtain on top of it.
function love.draw()
    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene then
        scene.draw()
    end

    draw_transition()
end

-- Input callbacks below are forwarded to the current scene (when it defines the matching function).
-- Presses, moves, text and keys are ignored during a wipe so nothing can hit a scene that is about to
-- change; mousereleased is not blocked, so a drag that began before the wipe can still end.
function love.mousepressed(x, y, button)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousepressed then
        scene.mousepressed(x, y, button)
    end
end

-- Mouse release; forwarded even during a wipe (see above).
function love.mousereleased(x, y, button)
    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousereleased then
        scene.mousereleased(x, y, button)
    end
end

-- Mouse move; ignored during a wipe.
function love.mousemoved(x, y)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousemoved then
        scene.mousemoved(x, y)
    end
end

-- Typed text (used by the connect menu); ignored during a wipe.
function love.textinput(t)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.textinput then
        scene.textinput(t)
    end
end

-- Key press; ignored during a wipe.
function love.keypressed(key)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.keypressed then
        scene.keypressed(key)
    end
end

-- Closes the ENet connection (and a server hosted by this player) on exit so the other side notices the
-- disconnect immediately.
function love.quit()
    require("network").close()
    server.stop()
end

-- Recomputes the global scale first, then lets the scene re-layout itself.
function love.resize(w, h)
    update_scale()

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.resize then
        scene.resize(w, h)
    end
end

return SceneManager
