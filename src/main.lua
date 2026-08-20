local love = require "love"


local BASE_SCALE = 2.6
local REFERENCE_WIDTH = 1920
local REFERENCE_HEIGHT = 1080

local function update_scale()
    if not love.graphics then return end
    local w, h = love.graphics.getDimensions()
    scale = BASE_SCALE * math.min(w / REFERENCE_WIDTH, h / REFERENCE_HEIGHT)
end

update_scale()

SceneManager = {}

SceneManager.scenes = {}
SceneManager.current_scene = nil

local TRANSITION_DURATION = 0.5
local TRANSITION_COLOR = {0.09, 0.09, 0.11}

local transition = {
    active = false,
    phase = nil,
    timer = 0,
    pending_name = nil,
    pending_args = nil,
    should_load = false
}

local function ease_out_cubic(t)
    local f = t - 1
    return f * f * f + 1
end

function SceneManager.add(name, scene)
    SceneManager.scenes[name] = scene
end

local function apply_switch(name, args, should_load)
    SceneManager.current_scene = name

    if should_load then
        local new = SceneManager.scenes[name]
        new.load(unpack(args))
    end
end

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

function SceneManager.switch(name, ...)
    begin_transition(name, {...}, true, nil)
end

function SceneManager.set(name)
    begin_transition(name, {}, false, nil)
end

function SceneManager.flash(on_covered)
    begin_transition(nil, nil, false, on_covered)
end

local function update_transition(dt)
    if not transition.active then return end

    transition.timer = transition.timer + dt

    if transition.phase == "cover" then
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

function love.load(arg)
    local is_server = false
    for _, value in ipairs(arg) do
        if value == "--server" then
            is_server = true
        end
    end

    if is_server then
        local server = require "server"
        SceneManager.add("server", server)
        SceneManager.switch("server")
        return
    end

    local game_client = require "scenes/game_client"
    local connect_menu = require "scenes/connect_menu"
    local layoff_scene = require "scenes/layoff_scene"

    SceneManager.add("game", game_client)
    SceneManager.add("menu", connect_menu)
    SceneManager.add("layoff", layoff_scene)


    SceneManager.switch("menu")
    -- SceneManager.switch("game", "127.0.0.1:6789")
end

function love.update(dt)
    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene then
        scene.update(dt)
    end

    update_transition(dt)
end


function love.draw()
    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene then
        scene.draw()
    end

    draw_transition()
end

function love.mousepressed(x, y, button)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousepressed then
        scene.mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousereleased then
        scene.mousereleased(x, y, button)
    end
end

function love.mousemoved(x, y, dx, dy)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.mousemoved then
        scene.mousemoved(x, y, dx, dy)
    end
end

function love.textinput(t)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.textinput then
        scene.textinput(t)
    end
end

function love.keypressed(key)
    if transition.active then return end

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.keypressed then
        scene.keypressed(key)
    end
end

function love.resize(w, h)
    update_scale()

    local scene = SceneManager.scenes[SceneManager.current_scene]

    if scene and scene.resize then
        scene.resize(w, h)
    end
end

return SceneManager
