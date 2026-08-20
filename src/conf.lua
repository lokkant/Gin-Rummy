local love = require "love"

function love.conf(t)
    t.console = false
    t.window.title = "Gin Rummy"
    t.window.resizable = true
    t.window.fullscreen = true
    t.window.highdpi = true

    local is_server = false
    for _, value in ipairs(arg) do
        if value == "--server" then
            is_server = true
            break
        end
    end

    if is_server then
        t.console = true
        t.window = nil
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.joystick = false
        t.modules.mouse = false
        t.modules.touch = false
        t.modules.video = false
    end
end

