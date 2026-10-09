-- Server settings files: the list of settings a host can change (SCHEMA, with labels and limits), reading and
-- writing the files in the save directory's "server_configs" folder, and applying a set of settings to the
-- shared config table (config.lua) when a server is created. A file is a Lua table of config keys:
-- `return {idle_warning_start = 20, horror_enabled = false}`; keys that are missing keep their normal value.
-- The forms of scenes/host_setup.lua and scenes/config_editor.lua are built from SCHEMA. Used by those
-- scenes and by main.lua (`--config`).
--
-- Before a server is created the host's own settings are put back (reset), so the settings of an earlier
-- game never stay behind.

local love = require "love"
local config = require "config"

local server_config = {}

-- Folder (inside the save directory) that holds the settings files, and the extension of the files.
local FOLDER = "server_configs"
local EXTENSION = ".lua"
-- Longest file name (without the extension) the editor accepts.
server_config.MAX_NAME_LENGTH = 32

-- Makes the schema entry of a number setting: key, label, limits and (optional) whole numbers only.
local function number(key, label, min, max, integer)
    return {key = key, label = label, kind = "number", min = min, max = max, integer = integer}
end

-- Makes the schema entry of an ON/OFF setting.
local function bool(key, label)
    return {key = key, label = label, kind = "bool"}
end

-- Every setting of config.lua in the order the editor shows them. A section is {title = "..."}; a setting is
-- {key, label, kind = "number" or "bool", min, max, integer (whole numbers only)}. A test keeps this list
-- in step with config.lua.
server_config.SCHEMA = {
    {title = "Time for each phase of a turn"},
    number("idle_warning_start", "Eye starts to redden after (s)", 0, 3600),
    number("idle_warning_full_delay", "Eye is fully red after another (s)", 0, 3600),
    number("idle_crack_delay", "Glass cracks after another (s)", 0, 3600),
    number("idle_loss_delay", "Round is lost after the crack (s)", 0, 3600),
    number("timeout_penalty", "Points for a round lost by waiting", 0, 1000, true),
    number("turn_ack_wait", "Longest wait for a client to show a turn (s)", 1, 600),

    {title = "Timers get shorter as the match goes on"},
    bool("timer_shrink_enabled", "Shorter timers"),
    number("timer_shrink_every", "Every this many rounds", 0, 100, true),
    number("timer_shrink_factor", "Each step multiplies the times by", 0.05, 1),
    number("timer_shrink_min_factor", "But never below this share", 0.05, 1),

    {title = "Horror mode (the switch is for both players, the rest changes the host's own screen)"},
    bool("horror_enabled", "Horror mode"),
    number("horror_intensity", "Intensity (0..1)", 0, 1),
    number("darkness_unlit", "Brightness of the unlit part (0..1)", 0, 1),
    bool("watchers_enabled", "Watching eyes"),
    number("watchers_count", "Pairs of eyes", 0, 4, true),
    number("watchers_alpha", "Visibility of the eyes (0..1)", 0, 1),
    number("watchers_idle_time", "Cursor away for (s) before they appear", 0, 600),
    number("watchers_fade_time", "Time they need to vanish (s)", 0.05, 60),
    number("watchers_distance", "Cursor distance that scares them (px at 1080p)", 0, 2000),
    bool("ambient_enabled", "Faint hum"),
    number("ambient_volume", "Hum volume (0..1)", 0, 1),
    number("ambient_on_min", "Hum is on for at least (s)", 0, 3600),
    number("ambient_on_max", "Hum is on for at most (s)", 0, 3600),
    number("ambient_off_min", "Hum is gone for at least (s)", 0, 3600),
    number("ambient_off_max", "Hum is gone for at most (s)", 0, 3600),
    bool("room_reverb", "Opponent's sounds through a wall"),
    bool("silence_on_stress", "Hum fades while the player hesitates"),
    bool("phantom_enabled", "Phantom card rustle"),
    number("phantom_interval_min", "Rustle: shortest wait (s)", 1, 3600),
    number("phantom_interval_max", "Rustle: longest wait (s)", 1, 3600),
    number("phantom_volume", "Rustle volume (0..1)", 0, 1),
    bool("knock_enabled", "Muffled knock"),
    number("knock_interval_min", "Knock: shortest wait (s)", 1, 3600),
    number("knock_interval_max", "Knock: longest wait (s)", 1, 3600),
    number("knock_volume", "Knock volume (0..1)", 0, 1),
    bool("face_gaze_enabled", "Kings and queens look at the cursor"),
    number("face_gaze_delay", "Delay of their gaze (s)", 0, 10),
    number("card_nervousness", "Card sway multiplier (1 = calm)", 0, 10),
    bool("opponent_restlessness", "Opponent's fan spreads while they hesitate"),
    number("deck_breathing", "Breathing of the stock (0 = none)", 0, 0.2),
    bool("eye_peek_enabled", "Eye peeks in the opponent's turn"),
    number("eye_peek_interval_min", "Peek: shortest wait (s)", 1, 3600),
    number("eye_peek_interval_max", "Peek: longest wait (s)", 1, 3600),
    number("eye_peek_duration", "Peek lasts (s)", 0.1, 60),
    number("eye_peek_openness", "How wide the eye opens (0..1)", 0, 1),
    bool("opponent_heartbeat_enabled", "Opponent's heartbeat"),
    number("opponent_heartbeat_volume", "Heartbeat volume (0..1)", 0, 1),

    {title = "The eye, the cracks and the volume"},
    number("capillaries_base", "Red vessels when calm (0..1)", 0, 1),
    number("stress_recovery_speed", "Redness fades at (per s)", 0.01, 100),
    number("crack_restore_time", "Cracks heal in (s)", 0.1, 100),
    number("crack_alpha", "Opacity of the cracks (0..1)", 0, 1),
    number("sound_volume", "Sound volume (0..1)", 0, 1),
    number("failure_volume", "Invalid move sound volume (0..1)", 0, 1),
    number("opponent_card_volume", "Opponent's card sounds (0..1)", 0, 1)
}

-- The settings as they were when this module was loaded (config.lua with the player's user_config.lua), so
-- that reset() can bring them back.
local base = {}
for key, value in pairs(config) do
    base[key] = value
end

-- Returns the entry of SCHEMA for a key, or nil.
local function find_entry(key)
    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.key == key then return entry end
    end
    return nil
end

-- Returns the value cut to the limits of its entry (and rounded for whole numbers), or nil when it is not
-- the right kind of value or not a usable number.
local function clean_value(entry, value)
    if entry.kind == "bool" then
        if type(value) == "boolean" then return value end
        return nil
    end

    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end

    if entry.integer then value = math.floor(value + 0.5) end
    return math.max(entry.min, math.min(entry.max, value))
end

-- Returns the settings table made of the usable values in `raw` (unknown keys and bad values are dropped).
function server_config.sanitize(raw)
    local clean = {}

    if type(raw) ~= "table" then return clean end

    for key, value in pairs(raw) do
        local entry = type(key) == "string" and find_entry(key) or nil
        local cleaned = entry and clean_value(entry, value)

        if cleaned ~= nil then
            clean[key] = cleaned
        end
    end

    return clean
end

-- Checks one typed value of a form: returns the clean value, or nil and a message for the player.
function server_config.check_value(key, value)
    local entry = find_entry(key)
    if entry == nil then return nil, "Unknown setting" end

    local cleaned = clean_value(entry, value)
    if cleaned == nil then return nil, "Not a valid value" end
    if entry.integer and value ~= math.floor(value) then
        return nil, entry.label .. " must be a whole number"
    end
    if cleaned ~= value then
        return nil, string.format("%s must be between %s and %s", entry.label, entry.min, entry.max)
    end

    return cleaned
end

-- Runs the text of a settings file without access to anything (an empty environment) and returns the
-- cleaned settings, or nil and a message when it is not a table of settings.
function server_config.parse(text)
    local chunk, problem = loadstring(text)
    if chunk == nil then return nil, "The file is not valid: " .. tostring(problem) end

    setfenv(chunk, {})
    local ok, result = pcall(chunk)

    if not ok or type(result) ~= "table" then
        return nil, "The file must return a table of settings"
    end

    return server_config.sanitize(result)
end

-- Puts the host's own settings back (the ones from before any server file was applied).
function server_config.reset()
    for key, value in pairs(base) do
        config[key] = value
    end
end

-- Sets the given settings (already clean, see sanitize) in the shared config table.
function server_config.apply(values)
    for key, value in pairs(values) do
        config[key] = value
    end
end

-- Returns the host's own value of every setting of the editor as a table (what a file would hold in
-- full), optionally with the settings of `overrides` (clean values) put over them.
function server_config.base_values(overrides)
    local values = {}

    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.key then values[entry.key] = base[entry.key] end
    end

    for key, value in pairs(overrides or {}) do
        values[key] = value
    end

    return values
end

-- Returns the names (without extension) of the settings files in the save folder, sorted.
function server_config.list_files()
    local names = {}

    for _, file in ipairs(love.filesystem.getDirectoryItems(FOLDER)) do
        local name = file:match("^(.+)%" .. EXTENSION .. "$")
        if name and love.filesystem.getInfo(FOLDER .. "/" .. file, "file") then
            table.insert(names, name)
        end
    end

    table.sort(names)
    return names
end

-- Returns the cleaned settings of the file called `name` in the save folder, or nil and a message.
function server_config.read(name)
    local text = love.filesystem.read(FOLDER .. "/" .. name .. EXTENSION)
    if text == nil then return nil, "The file " .. name .. EXTENSION .. " was not found" end

    return server_config.parse(text)
end

-- Turns a typed file name into one that is safe to use (letters, digits, "_" and "-", at most
-- MAX_NAME_LENGTH long); returns nil when nothing is left.
function server_config.clean_name(text)
    local name = string.gsub(text or "", "[^%w_%-]", "")
    name = string.sub(name, 1, server_config.MAX_NAME_LENGTH)

    if name == "" then return nil end
    return name
end

-- Formats a number so that it reads back exactly and whole numbers have no ".0".
local function format_number(value)
    if value == math.floor(value) and math.abs(value) < 1e9 then
        return string.format("%d", value)
    end
    return string.format("%.10g", value)
end

-- Writes `values` (settings of the editor, table key -> value) to the file `name` in the save folder, with a
-- comment for every setting. Returns true, or false and a message.
function server_config.save(name, values)
    name = server_config.clean_name(name)
    if name == nil then return false, "Type a file name (letters, digits, _ and -)" end

    local lines = {
        "-- Server settings made with CREATE SERVER CONFIG. Choose this file when hosting a game",
        "-- (or start a headless server with --config " .. name .. ").",
        "return {"
    }

    local entries = {}
    for _, entry in ipairs(server_config.SCHEMA) do
        if entry.key and values[entry.key] ~= nil then
            table.insert(entries, entry)
        end
    end

    for index, entry in ipairs(entries) do
        local value = values[entry.key]
        local text = type(value) == "boolean" and tostring(value) or format_number(value)
        local comma = index < #entries and "," or ""
        table.insert(lines, string.format("    %s = %s%s -- %s", entry.key, text, comma, entry.label))
    end

    table.insert(lines, "}")
    table.insert(lines, "")

    love.filesystem.createDirectory(FOLDER)
    local ok, problem = love.filesystem.write(FOLDER .. "/" .. name .. EXTENSION, table.concat(lines, "\n"))

    if not ok then return false, "Could not save the file: " .. tostring(problem) end
    return true, name
end

-- Takes a settings file from anywhere on the computer (a file dropped on the window: its path and text) and
-- stores a copy in the save folder under its own name. Returns the name, or nil and a message.
function server_config.import(path, text)
    local values, problem = server_config.parse(text)
    if values == nil then return nil, problem end

    local base_name = path:match("([^/\\]+)$") or path
    local name = server_config.clean_name((base_name:gsub("%.lua$", "")))
    if name == nil then return nil, "The file name has no usable letters" end

    love.filesystem.createDirectory(FOLDER)
    local ok, write_problem = love.filesystem.write(FOLDER .. "/" .. name .. EXTENSION, text)
    if not ok then return nil, "Could not copy the file: " .. tostring(write_problem) end

    return name
end

-- Returns the save folder's full path (to show to the player).
function server_config.get_folder_path()
    return love.filesystem.getSaveDirectory() .. "/" .. FOLDER
end

-- Returns the cleaned settings of a file given on the command line (--config): the name of a file in the
-- save folder, or a path to any Lua file. Returns nil and a message when it can't be used.
function server_config.read_argument(argument)
    local values = server_config.read((argument:gsub("%.lua$", "")))
    if values ~= nil then return values end

    local file = io.open(argument, "r")
    if file == nil then return nil, "No settings file called " .. argument end

    local text = file:read("*a")
    file:close()

    return server_config.parse(text)
end

return server_config
