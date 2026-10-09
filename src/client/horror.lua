-- Switches of the unsettling effects (config.lua): every effect asks here whether it is on and how strong it
-- should be, so one master switch and one intensity slider control them all. The master switch is our own
-- setting (config.horror_enabled) and the host's choice for the match (the server sends it with every new
-- game and round, see horror.set_match_enabled): the effects only run when both allow them. Used by the
-- client modules that implement the effects.

local config = require "config"

local horror = {}

-- Whether the server of the current match allows the effects (true until it says otherwise).
local match_enabled = true

-- Remembers what the server said about the effects for the current match.
function horror.set_match_enabled(enabled)
    match_enabled = enabled ~= false
end

-- True when the master switch (ours and the match's) is on.
function horror.is_master_on()
    return config.horror_enabled and match_enabled
end

-- True when the master switch and the effect's own switch (a key of config.lua, e.g. "watchers_enabled")
-- are both on.
function horror.is_on(key)
    return horror.is_master_on() and config[key] == true
end

-- The overall strength multiplier of the effects, 0..1.
function horror.strength()
    return math.max(0, math.min(1, config.horror_intensity))
end

-- The size of a numeric setting (e.g. "deck_breathing"), scaled by the intensity; 0 when all effects are off.
function horror.amount(key)
    if not horror.is_master_on() then return 0 end
    return config[key] * horror.strength()
end

-- A multiplier setting (1 = unchanged, e.g. "card_nervousness") scaled by the intensity: 1 + (value - 1) *
-- intensity; 1 when all effects are off.
function horror.multiplier(key)
    if not horror.is_master_on() then return 1 end
    return 1 + (config[key] - 1) * horror.strength()
end

return horror
