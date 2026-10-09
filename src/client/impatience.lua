-- The player's "slow turn" effects (client side): while it is our turn and no game step is made, the
-- redness (stress) of the eye grows, then the glass cracks on the screen; when we move, both calm down
-- slowly. The numbers come from the server with "is_my_turn" (limits) and config.lua. Used by
-- client/hud.lua, which draws the eye and calls draw_cracks.

local love = require "love"
local config = require "config"
local cracks = require "client/cracks"

local impatience = {}

-- Seconds of the white flash that goes with the moment the glass breaks, and its opacity.
local FLASH_TIME = 0.12
local FLASH_ALPHA = 0.25

-- Creates the state:
--   stress      0..1, how red the eye is (0 = calm, 1 = fiery red, vessels at their maximum)
--   crack       the crack pattern while the glass is cracked (nil otherwise)
--   visibility  0..1, how much of the crack is left; falls from 1 while the glass heals
--   flash       seconds left of the white flash
function impatience.create()
    return {
        stress = 0,
        crack = nil,
        visibility = 0,
        flash = 0,
        rng = love.math.newRandomGenerator(love.math.random(1, 2 ^ 30))
    }
end

-- Limits value to [0, 1].
local function clamp01(value)
    return math.max(0, math.min(1, value))
end

-- Per frame. `timer` is the turn timer {elapsed, limits} of state (nil when the server sent no limits);
-- it is only counted while it is our turn (is_my_turn). The stress follows the clock exactly while it
-- rises and falls slowly afterwards. The glass cracks at once when the clock reaches the crack time and
-- heals gradually when the clock goes back (we made a game step) or the turn passed. dt is in seconds.
-- Returns true in the frame in which the glass breaks, so that the caller can play the sound.
function impatience.update(self, dt, timer, is_my_turn)
    local did_crack = false

    local is_waiting = is_my_turn and timer ~= nil
    local target = 0

    if is_waiting then
        timer.elapsed = timer.elapsed + dt

        local limits = timer.limits
        target = clamp01((timer.elapsed - limits.fade_start) / (limits.fade_full - limits.fade_start))
    end

    if target >= self.stress then
        self.stress = target
    else
        self.stress = math.max(target, self.stress - dt * config.stress_recovery_speed)
    end

    self.flash = math.max(0, self.flash - dt)

    if is_waiting and timer.elapsed >= timer.limits.crack then
        -- A cracked glass that is still healing breaks again with a new pattern.
        if self.crack == nil or self.visibility < 1 then
            self.crack = cracks.create(self.rng)
            self.visibility = 1
            self.flash = FLASH_TIME
            did_crack = true
        end
    elseif self.crack ~= nil then
        self.visibility = self.visibility - dt / config.crack_restore_time
        if self.visibility <= 0 then
            self.crack = nil
            self.visibility = 0
        end
    end

    return did_crack
end

-- Draws the cracks (radiating from the point (center_x, center_y), normally the eye) and the flash over
-- the whole window. Nothing happens while the glass is whole.
function impatience.draw(self, center_x, center_y)
    local w, h = love.graphics.getDimensions()

    if self.flash > 0 then
        love.graphics.setColor(1, 1, 1, FLASH_ALPHA * self.flash / FLASH_TIME)
        love.graphics.rectangle("fill", 0, 0, w, h)
    end

    if self.crack ~= nil then
        -- Pieces farther than `visible` (a part of the full reach) are already healed.
        cracks.draw(self.crack, self.visibility, config.crack_alpha, center_x, center_y, h)
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return impatience
