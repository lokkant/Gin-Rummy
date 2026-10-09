-- Sound effects of the game scene (client): the sound of a card (handed over, taken or put on the discard
-- pile), a soft "no" for an invalid move, the heartbeat that starts when a player takes too long, and the
-- crack of the screen when they take far too long (see client/impatience.lua). Every sound is played with
-- a slightly different pitch each time, so repeats do not sound identical. Used by client/hud.lua,
-- client/messages.lua, client/input.lua and scenes/layoff_scene.lua. Without an audio device (or with the
-- audio module disabled) everything here does nothing.

local love = require "love"
local config = require "config"

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

-- Seconds of the fade-out at the end of a shortened clip.
local FADE_TIME = 0.25
-- Largest random change of the pitch of crack and heartbeat sounds, up or down (0.06 = 6 %).
local PITCH_VARIATION = 0.06

-- template sources by file name (false when a file could not be loaded) and the clones now playing.
local templates = {}
local playing = {}

-- How many sounds of each kind were started since the program began: {crack, card, failure, heartbeat}.
-- Lets tests check that a sound was triggered without listening to it.
sounds.plays = {crack = 0, card = 0, failure = 0, heartbeat = 0}
-- The file, volume and pitch of the sound started last; also only for tests.
sounds.last_play = nil

-- Seconds until the next heartbeat is due, when the last card sound started and which card clip it used.
local heartbeat_timer = 0
local last_card_time = -1
local last_card_clip_index
local last_failure_time = -1

-- Returns the loaded source of a clip, or nil if audio is unavailable or the file is missing.
local function get_template(file)
    if not love.audio then return nil end

    if templates[file] == nil then
        local ok, source = pcall(love.audio.newSource, file, "static")
        templates[file] = ok and source or false
    end

    return templates[file] or nil
end

-- Starts a clone of `clip` at `volume` and `pitch` (the clone lets sounds of one clip overlap) and
-- remembers it as `kind` so that update() can fade it out. Returns false when the clip is not available.
local function play_clip(clip, kind, volume, pitch)
    local template = get_template(clip.file)
    if template == nil then return false end

    local source = template:clone()
    source:setPitch(pitch)
    source:setVolume(volume)
    source:play()

    table.insert(playing, {source = source, kind = kind, age = 0, length = clip.length, volume = volume})
    sounds.plays[kind] = sounds.plays[kind] + 1
    sounds.last_play = {file = clip.file, volume = volume, pitch = pitch}
    return true
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
-- quieter for the opponent's cards. Sounds that would follow the previous one by less than
-- MIN_CARD_INTERVAL are skipped.
function sounds.play_card(loudness)
    if config.sound_volume <= 0 or loudness <= 0 then return end

    local now = love.timer.getTime()
    if now - last_card_time < MIN_CARD_INTERVAL then return end

    local index = pick_card_clip_index()
    local clip = CARD_CLIPS[index]
    local volume = clip.volume * loudness * config.sound_volume *
                   (1 + (love.math.random() * 2 - 1) * CARD_VOLUME_VARIATION)
    local pitch = 1 + (love.math.random() * 2 - 1) * CARD_PITCH_VARIATION

    if play_clip(clip, "card", volume, pitch) then
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
