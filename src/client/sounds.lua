-- Sound effects of the game scene (client): the sound of a card (handed over, taken or put on the discard
-- pile), a soft "no" for an invalid move, the heartbeat that starts when a player takes too long, and the
-- crack of the screen when they take far too long (see client/impatience.lua). Also the unsettling
-- sounds: a faint hum that comes and goes, the opponent's duller heartbeat from one side, a very quiet
-- rustle of a card from the dark side now and then, a rare muffled knock, and a "wall" (low-pass filter
-- and reverb) on the sounds of the opponent's cards. Every sound is played with a slightly different pitch
-- each time, so repeats do not sound identical. Used by client/hud.lua, client/messages.lua,
-- client/input.lua and scenes/layoff_scene.lua. Without an audio device (or with the audio module
-- disabled) everything here does nothing.

local love = require "love"
local config = require "config"
local horror = require "client/horror"

local sounds = {}

-- The clips that suit a pane of glass cracking at once. volume: how loud the clip is played relative to
-- config.sound_volume (the loudest ones peak at 0 dBFS, so they are turned down a bit); length: seconds
-- after which the clip is faded out and stopped, for clips with a long tail (nil = play it all).
local CRACK_CLIPS = {
    {file = "assets/sounds/glass_02.wav", volume = 1.0},
    {file = "assets/sounds/glass_04.wav", volume = 0.75, length = 1.0},
    {file = "assets/sounds/glass_05.wav", volume = 0.8, length = 1.0}
}

-- The sounds of a card in play. A random one is played each time (never the same twice in a row), see
-- play_card.
local CARD_CLIPS = {
    {file = "assets/sounds/short-beep-of-cards_1.mp3", volume = 0.7},
    {file = "assets/sounds/short-beep-of-cards_2.mp3", volume = 0.7},
    {file = "assets/sounds/short-beep-of-cards_3.mp3", volume = 0.7}
}
-- Shortest time between two card sounds (a card is handed over about every 0.033 s when the game deals at
-- 60 frames per second, so every card gets its sound, but a very fast machine does not pile them up).
-- Largest random pitch change and largest random volume change of a card sound (0.08 = 8 %).
local MIN_CARD_INTERVAL = 0.03
local CARD_PITCH_VARIATION = 0.08
local CARD_VOLUME_VARIATION = 0.12

-- The soft sound of an invalid move. Its loudness is config.failure_volume. A new one is not started
-- within FAILURE_COOLDOWN seconds of the last (repeated clicks must not turn it into a buzz).
local FAILURE_CLIP = {file = "assets/sounds/failure.wav"}
local FAILURE_COOLDOWN = 0.3
local FAILURE_PITCH_VARIATION = 0.04

-- One double beat of the heart ("lub-dub").
local HEARTBEAT_CLIP = {file = "assets/sounds/heartbeat.wav", volume = 1.0}
-- Seconds between two heartbeats when the player has just started to hesitate (stress 0) and when they are
-- at their limit (stress 1); in between the heart speeds up with the stress.
local HEARTBEAT_CALM_INTERVAL = 1.1
local HEARTBEAT_PANIC_INTERVAL = 0.55
-- The heartbeat is quiet at first and gets louder: this volume factor at stress 0, 1 at stress 1.
local HEARTBEAT_MIN_VOLUME = 0.4
-- Seconds in which a heartbeat that is stopped (the glass cracked) fades out.
local STOP_FADE_TIME = 0.08

-- The opponent's heartbeat: the same clip, but lower and duller (pitch factor), from one side. Seconds
-- between its beats when they just started to hesitate and when they are at their limit; its volume factor
-- at stress 0 (1 at stress 1).
local OPPONENT_HEARTBEAT_PITCH = 0.72
local OPPONENT_HEARTBEAT_CALM_INTERVAL = 1.3
local OPPONENT_HEARTBEAT_PANIC_INTERVAL = 0.7
local OPPONENT_HEARTBEAT_MIN_VOLUME = 0.3
-- How far to the left or right (the listener is at 0) the opponent's heartbeat and the rustles are heard.
local SIDE_DISTANCE = 0.9

-- The phantom rustle: a card sound slowed down to this pitch range; it only comes when nothing has been
-- heard for PHANTOM_QUIET_TIME seconds.
local PHANTOM_PITCH_MIN = 0.55
local PHANTOM_PITCH_MAX = 0.75
local PHANTOM_QUIET_TIME = 4

-- The knocks: recordings of a knock on wood; one of them is played from one side, muffled, with a little
-- random pitch change (volume: relative to config.knock_volume; the clips peak at 0 dBFS).
local KNOCK_CLIPS = {
    {file = "assets/sounds/knock_1.wav", volume = 1.0},
    {file = "assets/sounds/knock_2.mp3", volume = 1.0},
    {file = "assets/sounds/knock_3.wav", volume = 1.0}
}
local KNOCK_PITCH_VARIATION = 0.1

-- The hum: a looping 8 second sound made in code (the sampling rate is low because it only has low tones).
local AMBIENT_RATE = 11025
local AMBIENT_SECONDS = 8
-- How fast the hum swells in and dies away when it comes and goes (per second, like AMBIENT_FOLLOW_SPEED).
local AMBIENT_GATE_SPEED = 0.4
-- How fast the hum fades with the player's stress (per second) and how long and how deep it dips when the
-- turn passes to the opponent.
local AMBIENT_FOLLOW_SPEED = 2
local AMBIENT_DUCK_TIME = 0.5
local AMBIENT_DUCK_LEVEL = 0.15

-- The sound modes of the pause menu, in the order the button cycles through them: everything, only the
-- sounds that belong to the game itself (ESSENTIAL_KINDS), nothing.
local MODES = {"all", "essential", "off"}
-- The kinds of sound (see sounds.plays) that stay in the "essential" mode: the glass, the cards, the sound of
-- an invalid move and our heartbeat. The rest (hum, the opponent's heartbeat, phantom rustle, knock) is
-- there to distract.
local ESSENTIAL_KINDS = {crack = true, card = true, failure = true, heartbeat = true}
local mode_index = 1

-- Seconds of the fade-out at the end of a shortened clip.
local FADE_TIME = 0.25
-- Largest random change of the pitch of crack and heartbeat sounds, up or down (0.06 = 6 %).
local PITCH_VARIATION = 0.06

-- template sources by file name (false when a file could not be loaded) and the clones now playing.
local templates = {}
local playing = {}

-- How many sounds of each kind were started since the program began: {crack, card, failure, heartbeat}.
-- Lets tests check that a sound was triggered without listening to it.
sounds.plays = {crack = 0, card = 0, failure = 0, heartbeat = 0, opponent_heartbeat = 0, phantom = 0,
                knock = 0}
-- The file, volume, pitch, wall (muffled) and side of the sound started last; also only for tests.
sounds.last_play = nil

-- Seconds until the next heartbeat (ours / the opponent's) is due, and the side the opponent's is heard from.
local heartbeat_timer = 0
local opponent_heartbeat_timer = 0
local opponent_heartbeat_side
-- Seconds until the next phantom rustle may come (nil = not drawn yet).
local phantom_timer = nil
-- Seconds until the next knock may come (nil = not drawn yet) and the clip used last.
local knock_timer = nil
local last_knock_index
-- The hum comes and goes: ambient_gate_open says whether it is "on" now, ambient_gate_timer the seconds
-- until it switches (nil = not drawn yet) and ambient_gate how loud it is because of that (0..1, it swells
-- slowly).
local ambient_gate_open = false
local ambient_gate_timer
local ambient_gate = 0
-- The hum: its source, how loud it is now relative to its full volume (0..1, follows the stress), the volume
-- it was given last (for tests), seconds left of the dip, and whether it was our turn in the last frame.
local ambient_source
local ambient_level = 1
sounds.ambient_volume_now = 0
local ambient_duck = 0
local was_my_turn = false
-- Time (love.timer.getTime) of the last real sound on the table; the phantom waits until it is long ago.
local last_activity_time = -100
-- Whether the "room" effect (reverb) is available: nil = not tried yet.
local room_effect_ready
-- When the last card sound started and which card clip it used.
local last_card_time = -1
local last_card_clip_index
local last_failure_time = -1

-- True when the current sound mode lets this kind of sound play.
local function is_kind_allowed(kind)
    local mode = MODES[mode_index]
    return mode == "all" or (mode == "essential" and ESSENTIAL_KINDS[kind] == true)
end

-- Returns the loaded source of a clip, or nil if audio is unavailable or the file is missing.
local function get_template(file)
    if not love.audio then return nil end

    if templates[file] == nil then
        local ok, source = pcall(love.audio.newSource, file, "static")
        templates[file] = ok and source or false
    end

    return templates[file] or nil
end

-- Returns a mono version of a clip (needed to place a sound to the left or right), or nil. Stereo files are
-- mixed down once.
local function get_mono_template(file)
    if not love.audio or not love.sound then return nil end

    local key = file .. "#mono"
    if templates[key] == nil then
        local ok, source = pcall(function()
            local data = love.sound.newSoundData(file)
            if data:getChannelCount() == 1 then
                return love.audio.newSource(data, "static")
            end

            local mono = love.sound.newSoundData(data:getSampleCount(), data:getSampleRate(), data:getBitDepth(), 1)
            for i = 0, data:getSampleCount() - 1 do
                mono:setSample(i, (data:getSample(i * 2) + data:getSample(i * 2 + 1)) / 2)
            end
            return love.audio.newSource(mono, "static")
        end)
        templates[key] = ok and source or false
    end

    return templates[key] or nil
end

-- Makes the "room" reverb once, if the audio system supports effects. Returns true when it can be used.
local function is_room_effect_ready()
    if room_effect_ready == nil then
        room_effect_ready = false

        if love.audio and love.audio.isEffectsSupported and love.audio.isEffectsSupported() then
            room_effect_ready = pcall(love.audio.setEffect, "room",
                                      {type = "reverb", decaytime = 2.8, density = 0.85, gain = 0.32})
        end
    end

    return room_effect_ready
end

-- Makes a source sound as if it came from behind a wall: a low-pass filter takes the highs away and the
-- room reverb is added. Does nothing without effect support or when config.room_reverb is off.
local function muffle(source)
    if not horror.is_on("room_reverb") or not is_room_effect_ready() then return end

    pcall(source.setFilter, source, {type = "lowpass", volume = 1, highgain = 0.25})
    pcall(source.setEffect, source, "room")
end

-- Starts a clone of `clip` at `volume` and `pitch` (the clone lets sounds of one clip overlap) and
-- remembers it as `kind` so that update() can fade it out. options (all optional): muffled = true plays it
-- "through a wall", side = a number (negative = left, positive = right) places it to one side and makes the
-- clip mono. Returns false when the clip is not available.
local function play_clip(clip, kind, volume, pitch, options)
    options = options or {}

    if not is_kind_allowed(kind) then return false end

    local template
    if options.side then
        template = get_mono_template(clip.file)
    else
        template = get_template(clip.file)
    end
    if template == nil then return false end

    local source = template:clone()
    source:setPitch(pitch)
    source:setVolume(volume)

    if options.muffled then muffle(source) end
    if options.side then
        source:setRelative(true)
        source:setPosition(options.side, 0, 0)
    end

    source:play()

    table.insert(playing, {source = source, kind = kind, age = 0, length = clip.length, volume = volume})
    sounds.plays[kind] = sounds.plays[kind] + 1
    sounds.last_play = {file = clip.file, volume = volume, pitch = pitch, muffled = options.muffled, side = options.side}

    -- phantom rustles and the heart are not "something happening" on the table
    if kind == "card" or kind == "failure" or kind == "crack" then
        last_activity_time = love.timer.getTime()
    end
    return true
end

-- Returns the current sound mode: "all", "essential" or "off".
function sounds.get_mode()
    return MODES[mode_index]
end

-- Switches to the next sound mode (all -> essential -> off -> all). Sounds that the new mode does not allow
-- are cut off at once.
function sounds.cycle_mode()
    mode_index = mode_index % #MODES + 1

    for i = #playing, 1, -1 do
        if not is_kind_allowed(playing[i].kind) then
            playing[i].source:stop()
            table.remove(playing, i)
        end
    end

    if MODES[mode_index] ~= "all" and ambient_source then
        ambient_source:stop()
        sounds.ambient_volume_now = 0
    end
end

-- Loads all clips now, so that the first sound does not stall the game while a file is read.
function sounds.load()
    for _, clip in ipairs(CRACK_CLIPS) do
        get_template(clip.file)
    end
    for _, clip in ipairs(CARD_CLIPS) do
        get_template(clip.file)
    end
    get_template(FAILURE_CLIP.file)
    get_template(HEARTBEAT_CLIP.file)
    get_mono_template(HEARTBEAT_CLIP.file)
    get_mono_template(CARD_CLIPS[1].file)
    for _, clip in ipairs(KNOCK_CLIPS) do
        get_mono_template(clip.file)
    end
    is_room_effect_ready()
end

-- Plays a random crack clip (at config.sound_volume, with a small random pitch change).
function sounds.play_crack()
    if config.sound_volume <= 0 then return end

    local clip = CRACK_CLIPS[love.math.random(#CRACK_CLIPS)]
    local volume = clip.volume * config.sound_volume
    play_clip(clip, "crack", volume, 1 + (love.math.random() * 2 - 1) * PITCH_VARIATION)
end

-- Returns a random index into CARD_CLIPS that differs from the last one used (when there is a choice).
local function pick_card_clip_index()
    if #CARD_CLIPS == 1 then return 1 end

    local index = love.math.random(#CARD_CLIPS - 1)
    if last_card_clip_index ~= nil and index >= last_card_clip_index then
        index = index + 1
    end
    return index
end

-- Plays the sound of a card: dealt or drawn into a hand, or put on the discard pile. A random clip is used
-- and every play differs a little from the others in pitch and volume. loudness (0..1) scales it, e.g.
-- quieter for the opponent's cards; behind_wall = true muffles it (the opponent's cards). Sounds that would
-- follow the previous one by less than MIN_CARD_INTERVAL are skipped.
function sounds.play_card(loudness, behind_wall)
    if config.sound_volume <= 0 or loudness <= 0 then return end

    local now = love.timer.getTime()
    if now - last_card_time < MIN_CARD_INTERVAL then return end

    local index = pick_card_clip_index()
    local clip = CARD_CLIPS[index]
    local volume = clip.volume * loudness * config.sound_volume *
                   (1 + (love.math.random() * 2 - 1) * CARD_VOLUME_VARIATION)
    local pitch = 1 + (love.math.random() * 2 - 1) * CARD_PITCH_VARIATION

    if play_clip(clip, "card", volume, pitch, {muffled = behind_wall}) then
        last_card_time = now
        last_card_clip_index = index
    end
end

-- Plays the soft sound of an invalid move (a move out of turn, a card that may not be played, ...). Quiet
-- on purpose (config.failure_volume), at most once per FAILURE_COOLDOWN seconds.
function sounds.play_failure()
    if config.sound_volume <= 0 or config.failure_volume <= 0 then return end

    local now = love.timer.getTime()
    if now - last_failure_time < FAILURE_COOLDOWN then return end

    local volume = config.failure_volume * config.sound_volume
    local pitch = 1 + (love.math.random() * 2 - 1) * FAILURE_PITCH_VARIATION

    if play_clip(FAILURE_CLIP, "failure", volume, pitch) then
        last_failure_time = now
    end
end

-- Per frame (dt in seconds) while a player is hesitating: plays a heartbeat every few seconds when
-- `is_beating` is true (the player has taken longer than the first limit and the glass has not cracked),
-- faster and louder the higher the stress (0..1) is. When it is false the timer is reset, so the next
-- time the heart starts at once.
function sounds.update_heartbeat(dt, stress, is_beating)
    if not is_beating or stress <= 0 or config.sound_volume <= 0 then
        heartbeat_timer = 0
        return
    end

    heartbeat_timer = heartbeat_timer - dt

    if heartbeat_timer <= 0 then
        local volume = (HEARTBEAT_MIN_VOLUME + (1 - HEARTBEAT_MIN_VOLUME) * stress) * HEARTBEAT_CLIP.volume *
                       config.sound_volume
        play_clip(HEARTBEAT_CLIP, "heartbeat", volume, 1 + (love.math.random() * 2 - 1) * PITCH_VARIATION * 0.5)

        heartbeat_timer = HEARTBEAT_CALM_INTERVAL + (HEARTBEAT_PANIC_INTERVAL - HEARTBEAT_CALM_INTERVAL) * stress
    end
end

-- Per frame while the opponent is thinking: when they have taken longer than the first limit (stress > 0)
-- their heart beats too - duller and lower than ours, from one side, and faster and louder the longer they
-- take. Same rules as update_heartbeat, but only when `is_beating` (their turn) and the effect is on.
function sounds.update_opponent_heartbeat(dt, stress, is_beating)
    if not is_beating or stress <= 0 or config.sound_volume <= 0 or not horror.is_on("opponent_heartbeat_enabled") then
        opponent_heartbeat_timer = 0
        opponent_heartbeat_side = nil
        return
    end

    opponent_heartbeat_timer = opponent_heartbeat_timer - dt

    if opponent_heartbeat_timer <= 0 then
        -- the first beat of a thinking spell picks the side it is heard from
        if opponent_heartbeat_side == nil then
            opponent_heartbeat_side = (love.math.random() < 0.5 and -1 or 1) * SIDE_DISTANCE
        end

        local volume = (OPPONENT_HEARTBEAT_MIN_VOLUME + (1 - OPPONENT_HEARTBEAT_MIN_VOLUME) * stress) *
                       config.opponent_heartbeat_volume * config.sound_volume * horror.strength()
        local pitch = OPPONENT_HEARTBEAT_PITCH * (1 + (love.math.random() * 2 - 1) * PITCH_VARIATION * 0.5)
        play_clip(HEARTBEAT_CLIP, "opponent_heartbeat", volume, pitch,
                  {muffled = true, side = opponent_heartbeat_side})

        opponent_heartbeat_timer = OPPONENT_HEARTBEAT_CALM_INTERVAL +
                                   (OPPONENT_HEARTBEAT_PANIC_INTERVAL - OPPONENT_HEARTBEAT_CALM_INTERVAL) * stress
    end
end

-- Per frame: now and then, when nothing has happened on the table for a while (`is_quiet`, and no real
-- sound for PHANTOM_QUIET_TIME seconds), a very quiet, slowed-down card rustle is heard from one side, as if
-- someone in the dark moved a card. The time between two rustles is random, between
-- config.phantom_interval_min and _max; it only runs down while it is quiet.
function sounds.update_phantom(dt, is_quiet)
    if not horror.is_on("phantom_enabled") or config.sound_volume <= 0 then return end

    if phantom_timer == nil then
        phantom_timer = config.phantom_interval_min +
                        love.math.random() * (config.phantom_interval_max - config.phantom_interval_min)
    end

    if not is_quiet then return end

    phantom_timer = phantom_timer - dt

    if phantom_timer <= 0 and love.timer.getTime() - last_activity_time >= PHANTOM_QUIET_TIME then
        local clip = CARD_CLIPS[love.math.random(#CARD_CLIPS)]
        local volume = config.phantom_volume * config.sound_volume * horror.strength()
        local pitch = PHANTOM_PITCH_MIN + love.math.random() * (PHANTOM_PITCH_MAX - PHANTOM_PITCH_MIN)
        local side = (love.math.random() < 0.5 and -1 or 1) * SIDE_DISTANCE * 1.3

        play_clip(clip, "phantom", volume, pitch, {muffled = true, side = side})
        phantom_timer = nil
    end
end

-- Per frame: very rarely, at a random time (config.knock_interval_min.._max seconds apart, counted only
-- while it is `is_quiet`), a muffled knock is heard from one side, as if someone knocked on the other side
-- of a wall.
function sounds.update_knock(dt, is_quiet)
    if not horror.is_on("knock_enabled") or config.sound_volume <= 0 then return end

    if knock_timer == nil then
        knock_timer = config.knock_interval_min +
                      love.math.random() * (config.knock_interval_max - config.knock_interval_min)
    end

    if not is_quiet then return end

    knock_timer = knock_timer - dt

    if knock_timer <= 0 then
        local index = love.math.random(#KNOCK_CLIPS)
        if index == last_knock_index then index = index % #KNOCK_CLIPS + 1 end
        last_knock_index = index

        local clip = KNOCK_CLIPS[index]
        local volume = clip.volume * config.knock_volume * config.sound_volume * horror.strength()
        local pitch = 1 + (love.math.random() * 2 - 1) * KNOCK_PITCH_VARIATION
        local side = (love.math.random() < 0.5 and -1 or 1) * SIDE_DISTANCE * 1.3

        play_clip(clip, "knock", volume, pitch, {muffled = true, side = side})
        knock_timer = nil
    end
end

-- Makes the looping hum (once): two low tones that beat slowly, a quiet octave and a bed of many very weak
-- tones that sounds like breathing noise. Every frequency has a whole number of periods in the 8 seconds, so
-- the loop has no seam. Returns the source, or nil without audio.
local function get_ambient_source()
    if ambient_source ~= nil then return ambient_source or nil end
    if not love.audio or not love.sound then return nil end

    local ok, source = pcall(function()
        local frames = AMBIENT_RATE * AMBIENT_SECONDS
        local data = love.sound.newSoundData(frames, AMBIENT_RATE, 16, 2)

        -- the bed: tones at multiples of 1/8 Hz between 20 and 200 Hz with random phases and amplitudes
        local rng = love.math.newRandomGenerator(5)
        local bed = {}
        for i = 1, 24 do
            bed[i] = {frequency = rng:random(160, 1600) / AMBIENT_SECONDS, phase = rng:random() * 2 * math.pi,
                      amplitude = 0.012 + rng:random() * 0.012}
        end

        local two_pi = 2 * math.pi
        for i = 0, frames - 1 do
            local t = i / AMBIENT_RATE
            local sample = 0.32 * math.sin(two_pi * 38 * t) + 0.24 * math.sin(two_pi * 38.75 * t) +
                           0.08 * math.sin(two_pi * 76.5 * t)

            for _, tone in ipairs(bed) do
                sample = sample + tone.amplitude * math.sin(two_pi * tone.frequency * t + tone.phase)
            end

            -- slow swell, two full periods in the loop
            sample = sample * (0.8 + 0.2 * math.sin(two_pi * 0.25 * t))

            data:setSample(i * 2, sample)
            data:setSample(i * 2 + 1, sample)
        end

        local new_source = love.audio.newSource(data, "static")
        new_source:setLooping(true)
        return new_source
    end)

    ambient_source = ok and source or false
    return ambient_source or nil
end

-- Per frame (dt in seconds): keeps the hum going at config.ambient_volume. It is not there all the time: it
-- swells in for config.ambient_on_min.._max seconds, then dies away for config.ambient_off_min.._max
-- seconds, and so on. It also fades away while the player hesitates (it follows 1 - stress, if
-- config.silence_on_stress) and dips for half a second when it is no longer our turn. Without the effect
-- the hum is stopped.
function sounds.update_ambient(dt, stress, is_my_turn)
    local source = nil
    if horror.is_on("ambient_enabled") and config.sound_volume > 0 and MODES[mode_index] == "all" then
        source = get_ambient_source()
    end

    if source == nil then
        if ambient_source then ambient_source:stop() end
        sounds.ambient_volume_now = 0
        return
    end

    -- the hum switches between "on" and "off" at random times
    if ambient_gate_timer == nil then
        ambient_gate_timer = config.ambient_off_min +
                             love.math.random() * (config.ambient_off_max - config.ambient_off_min)
    end

    ambient_gate_timer = ambient_gate_timer - dt
    if ambient_gate_timer <= 0 then
        ambient_gate_open = not ambient_gate_open
        local shortest = ambient_gate_open and config.ambient_on_min or config.ambient_off_min
        local longest = ambient_gate_open and config.ambient_on_max or config.ambient_off_max
        ambient_gate_timer = shortest + love.math.random() * (longest - shortest)
    end

    local gate_target = ambient_gate_open and 1 or 0
    ambient_gate = ambient_gate + (gate_target - ambient_gate) * math.min(1, dt * AMBIENT_GATE_SPEED)

    -- the turn just passed to the opponent: a short drop of the hum
    if was_my_turn and not is_my_turn then
        ambient_duck = AMBIENT_DUCK_TIME
    end
    was_my_turn = is_my_turn
    ambient_duck = math.max(0, ambient_duck - dt)

    local target = 1
    if config.silence_on_stress then target = 1 - stress end
    if ambient_duck > 0 then target = math.min(target, AMBIENT_DUCK_LEVEL) end

    ambient_level = ambient_level + (target - ambient_level) * math.min(1, dt * AMBIENT_FOLLOW_SPEED * (ambient_duck > 0 and 4 or 1))

    local volume = ambient_level * ambient_gate * config.ambient_volume * config.sound_volume *
                   horror.strength()
    sounds.ambient_volume_now = volume
    source:setVolume(volume)

    -- no need to keep it running while it is inaudible
    if volume < 0.0005 then
        if source:isPlaying() then source:stop() end
    elseif not source:isPlaying() then
        source:play()
    end
end

-- Stops the hum (when the game scene is left).
function sounds.stop_ambient()
    if ambient_source then ambient_source:stop() end
    sounds.ambient_volume_now = 0
    ambient_gate, ambient_gate_open, ambient_gate_timer = 0, false, nil
end

-- Silences the heart at once (almost: it fades out within STOP_FADE_TIME): the glass has cracked.
function sounds.stop_heartbeat()
    heartbeat_timer = 0

    for _, entry in ipairs(playing) do
        if entry.kind == "heartbeat" then
            entry.stopping = STOP_FADE_TIME
        end
    end
end

-- Per frame (dt in seconds): fades out and stops the clips that are cut short or being stopped, and
-- forgets finished ones.
function sounds.update(dt)
    for i = #playing, 1, -1 do
        local entry = playing[i]
        entry.age = entry.age + dt

        if entry.stopping then
            entry.stopping = entry.stopping - dt
            if entry.stopping <= 0 then
                entry.source:stop()
                table.remove(playing, i)
            else
                entry.source:setVolume(entry.volume * entry.stopping / STOP_FADE_TIME)
            end
        elseif not entry.source:isPlaying() then
            table.remove(playing, i)
        elseif entry.length and entry.age >= entry.length then
            entry.source:stop()
            table.remove(playing, i)
        elseif entry.length and entry.age > entry.length - FADE_TIME then
            entry.source:setVolume(entry.volume * (entry.length - entry.age) / FADE_TIME)
        end
    end
end

return sounds
