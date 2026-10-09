-- Sound effects of the game scene (client). At the moment only the crack of the screen when a player
-- takes too long (see client/impatience.lua): one of a few breaking-glass clips from assets/sounds/ is
-- played with a slightly different pitch each time, so repeated cracks do not sound identical. Used by
-- client/hud.lua. Without an audio device (or with the audio module disabled) everything here does nothing.

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

-- Seconds of the fade-out at the end of a shortened clip.
local FADE_TIME = 0.25
-- Largest random change of the pitch up or down (0.06 = 6 %).
local PITCH_VARIATION = 0.06

-- template sources by file name (false when a file could not be loaded) and the clones now playing.
local templates = {}
local playing = {}

-- Returns the loaded source of a clip, or nil if audio is unavailable or the file is missing.
local function get_template(file)
    if not love.audio then return nil end

    if templates[file] == nil then
        local ok, source = pcall(love.audio.newSource, file, "static")
        templates[file] = ok and source or false
    end

    return templates[file] or nil
end

-- Loads all clips now, so that the first crack does not stall the game while a file is read.
function sounds.load()
    for _, clip in ipairs(CRACK_CLIPS) do
        get_template(clip.file)
    end
end

-- Plays a random crack clip (at config.sound_volume, with a small random pitch change). A clone of the
-- loaded source is played, so a new crack may start while the previous one still sounds.
function sounds.play_crack()
    if config.sound_volume <= 0 then return end

    local clip = CRACK_CLIPS[love.math.random(#CRACK_CLIPS)]
    local template = get_template(clip.file)
    if template == nil then return end

    local source = template:clone()
    local volume = clip.volume * config.sound_volume

    source:setPitch(1 + (love.math.random() * 2 - 1) * PITCH_VARIATION)
    source:setVolume(volume)
    source:play()

    table.insert(playing, {source = source, age = 0, length = clip.length, volume = volume})
end

-- Per frame (dt in seconds): fades out and stops the clips that are cut short, and forgets finished ones.
function sounds.update(dt)
    for i = #playing, 1, -1 do
        local entry = playing[i]
        entry.age = entry.age + dt

        if not entry.source:isPlaying() then
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
