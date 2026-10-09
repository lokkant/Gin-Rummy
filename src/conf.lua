-- LOVE configuration, executed by LOVE before main.lua. Client: resizable fullscreen window. Server
-- (`--server`): console on, no window, and the graphics/audio/input modules are switched off so it can run
-- headless (love.timer, love.math and love.data stay on: server_deck.lua needs them).

local love = require "love"

-- Fills the config table `t`; called once at startup. `arg` is the command line list.
function love.conf(t)
    t.console = false
    t.window.title = "Gin Rummy"
    t.window.resizable = true
    t.window.fullscreen = true
    t.window.highdpi = true

    -- main.lua parses the same flag in love.load, but that runs too late to change the modules.
    local is_server = false
    for _, value in ipairs(arg) do
        if value == "--server" then
            is_server = true
            break
        end
    end

    if is_server then
        t.console = true
        -- No window at all; the modules below can only be disabled together with it.
        t.window = nil
        t.modules.graphics = false
        t.modules.audio = false
        t.modules.joystick = false
        t.modules.mouse = false
        t.modules.touch = false
        t.modules.video = false
    end
end

