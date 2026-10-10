-- A pixel-art eye on the table, opposite the stock pile (client side). It is awake - open, and its pupil
-- follows the mouse - while it is the player's turn, and asleep (closed, with lashes) otherwise; it opens
-- and closes smoothly and blinks now and then. Thin red vessels show on the white of the eye; they sit on
-- the eyeball, so they turn with the iris when it looks around, and a pulse of blood runs along them. When
-- the player takes too long (`stress`, 0..1, set by client/hud.lua) the vessels spread, darken and throb
-- faster, the white gets pink and the iris turns into flickering fire. The picture is drawn pixel by pixel
-- into a small image every frame (the eye has no sprite file) and drawn enlarged with the nearest filter,
-- like the card art. Used by client/hud.lua.

local love = require "love"
local config = require "config"

local eye = {}

-- Size of the picture in its own pixels and its centre.
local WIDTH = 61
local HEIGHT = 41
local CENTER_X = 30
local CENTER_Y = 20

-- Half height of the opening in the middle column when the eye is fully open; towards the corners it
-- shrinks to 0, which gives the almond shape.
local OPENING_HEIGHT = 17
-- Radii of the iris and of the pupil.
local IRIS_RADIUS = 11
local PUPIL_RADIUS = 5

-- The iris can move this far from the centre horizontally / vertically (the opening is wide but low).
local MAX_LOOK_X = 14
local MAX_LOOK_Y = 7
-- Eye pixels the iris moves per eye pixel the cursor is away from the eye's centre.
local LOOK_SENSITIVITY = 0.18
-- How fast the iris follows the cursor and how fast the eyelids move (per second): opening to look at the
-- cursor, opening only a slit (a peek), closing. The remaining distance shrinks by this factor each second.
local LOOK_SPEED = 18
local OPEN_SPEED = 9
local PEEK_OPEN_SPEED = 3.5
local CLOSE_SPEED = 5
-- The lids never move slower than this (openness units per second), so the last bit of closing does not
-- drag on.
local MIN_LID_SPEED = 0.5

-- Below this openness the columns where the slit is thinner than a pixel are drawn as the lid line.
local LID_LINE_BELOW = 0.1
-- Below this openness the eye is drawn as the closed (sleeping) line instead of a thin slit.
local CLOSED_BELOW = 0.03
-- Seconds a blink lasts, and the range of seconds between two blinks.
local BLINK_DURATION = 0.18
local BLINK_MIN_PAUSE = 2
local BLINK_MAX_PAUSE = 6

-- Colours as 0..1 RGB.
local OUTLINE = {38 / 255, 24 / 255, 40 / 255}
local SCLERA = {240 / 255, 236 / 255, 226 / 255}
local SCLERA_SHADE = {205 / 255, 196 / 255, 186 / 255}
local IRIS_INNER = {232 / 255, 172 / 255, 52 / 255}
local IRIS_OUTER = {204 / 255, 128 / 255, 34 / 255}
local IRIS_RING = {140 / 255, 85 / 255, 20 / 255}
local PUPIL = {15 / 255, 10 / 255, 12 / 255}
-- The red-eyed look: fire colours for the iris at full stress, the pink the white takes on, and the colour
-- of a vessel when it is faint and when it is at its darkest.
local FIRE_INNER = {255 / 255, 96 / 255, 28 / 255}
local FIRE_OUTER = {214 / 255, 28 / 255, 10 / 255}
local FIRE_RING = {110 / 255, 8 / 255, 6 / 255}
local FIRE_GLOW = {255 / 255, 205 / 255, 70 / 255}
local SCLERA_BLOODSHOT = {255 / 255, 214 / 255, 205 / 255}
local VESSEL_FAINT = {226 / 255, 150 / 255, 150 / 255}
local VESSEL_DARK = {190 / 255, 25 / 255, 30 / 255}
-- Number of main vessels and how many side branches each can get.
local VESSEL_COUNT = 18
local BRANCHES_PER_VESSEL = 2
local HIGHLIGHT = {1, 1, 1}

-- The picture: pixels are written into image_data and shown through image.
local image_data
local image
-- opening_height[x] = half height of the opening in column x when fully open (0 at both corners).
-- closed_droop[x] = how many pixels below the middle row the closed lid line lies in column x (the line is
-- an arc that sags in the middle); a closing eye slides its slit down onto that line.
local opening_height = {}
local closed_droop = {}
-- The vessels live on the eyeball, so their pixels are stored relative to the centre of the iris, not to
-- the picture: wherever the iris looks, the same pattern moves with it. VESSEL_RANGE_X / _Y are the
-- largest offsets that are stored (a bit more than the opening, so there is something to show when the
-- eyeball turns).
-- vessel_threshold[key] = how much of the vessels must be shown for that pixel to be red (0..1; main vessels
-- have low thresholds and are always seen a bit); vessel_phase[key] = how far along its vessel the pixel is,
-- 0 at the edge and 1 at the iris, which the blood pulse uses. Both are absent where there is no vessel.
local VESSEL_RANGE_X = 38
local VESSEL_RANGE_Y = 28
local vessel_threshold = {}
local vessel_phase = {}

-- Key of the stored vessel pixel at offset (dx, dy) from the iris centre, or nil outside the stored range.
local function get_vessel_key(dx, dy)
    if dx < -VESSEL_RANGE_X or dx > VESSEL_RANGE_X or dy < -VESSEL_RANGE_Y or dy > VESSEL_RANGE_Y then
        return nil
    end
    return (dy + VESSEL_RANGE_Y) * (2 * VESSEL_RANGE_X + 1) + (dx + VESSEL_RANGE_X)
end

-- Mixes two colours: 0 gives a, 1 gives b.
local function mix(a, b, amount)
    return {a[1] + (b[1] - a[1]) * amount, a[2] + (b[2] - a[2]) * amount, a[3] + (b[3] - a[3]) * amount}
end

-- Remembers that the pixel at offset (dx, dy) from the iris belongs to a vessel that shows from `threshold`
-- on (the lowest wins), `phase` of the way from the edge to the iris.
local function set_vessel_pixel(dx, dy, threshold, phase)
    local key = get_vessel_key(dx, dy)
    if key == nil then return end

    if vessel_threshold[key] == nil or vessel_threshold[key] > threshold then
        vessel_threshold[key] = threshold
        vessel_phase[key] = phase
    end
end

-- Grows one crooked vessel from the offset (dx, dy) towards the iris until it touches the iris. `base` is
-- the threshold of its start; the tip needs a bit more. Returns the list of its pixels so that branches can
-- start from them.
local function grow_vessel(rng, dx, dy, base)
    local pixels = {}
    local reach = math.sqrt(dx * dx + dy * dy) - (IRIS_RADIUS + 1)
    local walked = 0

    while walked < reach do
        local length = math.sqrt(dx * dx + dy * dy)
        dx = dx - dx / length + (rng:random() - 0.5) * 1.1
        dy = dy - dy / length + (rng:random() - 0.5) * 1.1
        walked = walked + 1

        local pixel_x, pixel_y = math.floor(dx + 0.5), math.floor(dy + 0.5)
        set_vessel_pixel(pixel_x, pixel_y, base + 0.3 * walked / reach, walked / reach)
        table.insert(pixels, {pixel_x, pixel_y})
    end

    return pixels
end

-- Builds the vessel pattern (always the same, from a fixed seed): main vessels start all around, outside the
-- opening, and run to the iris; each gets a few short branches.
local function make_vessels()
    local rng = love.math.newRandomGenerator(11)

    for i = 1, VESSEL_COUNT do
        local angle = (i - 1) / VESSEL_COUNT * 2 * math.pi + (rng:random() - 0.5) * 0.25
        local base = rng:random() * 0.6

        local pixels = grow_vessel(rng, math.cos(angle) * 36, math.sin(angle) * 26, base)

        for _ = 1, BRANCHES_PER_VESSEL do
            if #pixels > 6 then
                local origin = pixels[rng:random(3, #pixels)]
                local branch = grow_vessel(rng, origin[1] + rng:random(-3, 3), origin[2] + rng:random(-3, 3),
                                           math.min(0.95, base + 0.25))
                for _, pixel in ipairs(branch) do
                    set_vessel_pixel(pixel[1], pixel[2], math.min(1, base + 0.4), 0.5)
                end
            end
        end
    end
end

-- Makes the shared picture buffers and the column heights (once).
local function prepare()
    if image_data ~= nil then return end

    image_data = love.image.newImageData(WIDTH, HEIGHT)
    image = love.graphics.newImage(image_data)
    image:setFilter("nearest", "nearest")

    for x = 0, WIDTH - 1 do
        local t = (x - CENTER_X) / CENTER_X
        opening_height[x] = math.floor(OPENING_HEIGHT * (1 - t * t) ^ 0.7 + 0.5)
        closed_droop[x] = math.floor(4 * (1 - t * t) ^ 0.8 + 0.5)
    end

    make_vessels()
end

-- Creates the state of one eye: closed at first, with the iris in the middle. `stress` (0..1) is set from
-- outside every frame.
function eye.create()
    return {
        stress = 0,
        openness = 0,
        look_x = 0,
        look_y = 0,
        blink_timer = love.math.random() * (BLINK_MAX_PAUSE - BLINK_MIN_PAUSE) + BLINK_MIN_PAUSE,
        blink_time = 0
    }
end

-- Limits value to [-limit, limit].
local function clamp(value, limit)
    return math.max(-limit, math.min(limit, value))
end

-- Per frame: opens or closes the lids (is_awake), blinks from time to time while open and turns the iris
-- towards the cursor (mouse_x, mouse_y), given the eye's centre on the screen and the size of one eye pixel
-- on the screen. dt is in seconds. peek_openness (optional, 0..1): while not awake the lids stay open this
-- far and the eye looks up, as if watching the opponent's cards through a slit.
function eye.update(self, dt, is_awake, mouse_x, mouse_y, screen_x, screen_y, pixel_size, peek_openness)
    local target_openness = is_awake and 1 or (peek_openness or 0)
    local delta = target_openness - self.openness

    -- Opening is quicker than closing, a peek opens slowly, and a minimum speed finishes the move.
    local speed = CLOSE_SPEED
    if delta > 0 then
        speed = is_awake and OPEN_SPEED or PEEK_OPEN_SPEED
    end

    local step = delta * math.min(1, dt * speed)
    local min_step = math.min(math.abs(delta), MIN_LID_SPEED * dt)
    if math.abs(step) < min_step then
        step = delta > 0 and min_step or -min_step
    end
    self.openness = self.openness + step

    if is_awake and self.openness > 0.95 then
        self.blink_timer = self.blink_timer - dt
        if self.blink_timer <= 0 then
            self.blink_time = BLINK_DURATION
            self.blink_timer = love.math.random() * (BLINK_MAX_PAUSE - BLINK_MIN_PAUSE) + BLINK_MIN_PAUSE
        end
    end
    self.blink_time = math.max(0, self.blink_time - dt)

    local target_x, target_y = 0, 0
    if is_awake then
        target_x = clamp((mouse_x - screen_x) / pixel_size * LOOK_SENSITIVITY, MAX_LOOK_X)
        target_y = clamp((mouse_y - screen_y) / pixel_size * LOOK_SENSITIVITY, MAX_LOOK_Y)
    elseif peek_openness then
        -- half open and looking up: towards the opponent's cards at the top of the table
        target_y = -MAX_LOOK_Y
    elseif self.openness > CLOSED_BELOW then
        -- the lids are still closing: the gaze stays where it was and goes out of sight with them
        target_x, target_y = self.look_x, self.look_y
    end

    local follow = math.min(1, dt * LOOK_SPEED)
    self.look_x = self.look_x + (target_x - self.look_x) * follow
    self.look_y = self.look_y + (target_y - self.look_y) * follow
end

-- Returns the colour of the closed eye at (x, y), or nil if the pixel is empty: a downward arc two pixels
-- thick with short lashes under it.
local function get_closed_color(x, y)
    if opening_height[x] < 1 then return nil end

    local line_y = CENTER_Y + closed_droop[x]

    if y == line_y or y == line_y - 1 then
        return OUTLINE
    end

    -- lashes: every tenth column, two pixels long
    if x % 10 == 0 and (y == line_y + 1 or y == line_y + 2) then
        return OUTLINE
    end

    return nil
end

-- Returns the colour of the pixel (x, y) of the open eye, or nil if it is outside. `openness` (0..1)
-- narrows the opening from the top and the bottom; (iris_x, iris_y) is the iris centre; stress (0..1)
-- reddens the eye and `time` (seconds) animates the fire of the iris.
local function get_open_color(x, y, openness, iris_x, iris_y, stress, time)
    local visible = opening_height[x] * openness
    -- A closing eye lowers its slit onto the line of the closed eye, so that it ends up where the sleeping
    -- eye is drawn (squared: the lids come together mostly in the last part).
    local lowered = math.floor(closed_droop[x] * (1 - openness) ^ 2 + 0.5)
    local dy = y - (CENTER_Y + lowered)

    -- Where the slit has become thinner than a pixel while the eye is nearly shut, the lids have met: two
    -- rows of lid line, the same as the sleeping eye (so the last frames of closing look like it).
    if openness < LID_LINE_BELOW and visible < 1 then
        if opening_height[x] >= 1 and (dy == 0 or dy == -1) then return OUTLINE end
        return nil
    end
    local abs_dy = math.abs(dy)

    if abs_dy > visible + 1 then return nil end
    if abs_dy > visible or opening_height[x] < 1 then return OUTLINE end

    local to_iris = math.sqrt((x - iris_x) ^ 2 + (y - iris_y) ^ 2)
    local color

    if to_iris <= PUPIL_RADIUS then
        color = PUPIL
    elseif to_iris <= IRIS_RADIUS then
        if to_iris > IRIS_RADIUS - 2 then
            color = mix(IRIS_RING, FIRE_RING, stress)
        elseif to_iris < 8 then
            color = mix(IRIS_INNER, FIRE_INNER, stress)
        else
            color = mix(IRIS_OUTER, FIRE_OUTER, stress)
        end

        -- Flames: bright tongues run round the pupil, more of them the redder the eye is.
        if stress > 0.2 and to_iris < IRIS_RADIUS - 2 then
            local angle = math.atan2(y - iris_y, x - iris_x)
            local flicker = 0.5 + 0.5 * math.sin(angle * 5 + time * 9 - to_iris * 0.9)
            color = mix(color, FIRE_GLOW, flicker * stress * 0.5)
        end

        -- the upper lid shades the top of the iris
        if dy < -visible + 3 then
            color = {color[1] * 0.7, color[2] * 0.7, color[3] * 0.7}
        end
    else
        color = mix(SCLERA, SCLERA_BLOODSHOT, stress * 0.5)
        if abs_dy >= visible - 1 then
            color = SCLERA_SHADE
        end

        -- Red vessels: some are always faintly there, more and darker ones the higher the stress is. They
        -- are looked up relative to the iris, so they move with it. Two kinds of motion: the whole network
        -- throbs with a heartbeat that gets faster with the stress, and a bright pulse of blood runs
        -- along every vessel towards the iris.
        local key = get_vessel_key(x - iris_x, y - iris_y)
        local threshold = key and vessel_threshold[key]
        local shown = config.capillaries_base + (1 - config.capillaries_base) * stress
        if threshold ~= nil and threshold <= shown then
            local strength = math.min(1, (shown - threshold) * 5)
            local throb = 0.92 + 0.08 * math.sin(time * (2.5 + 5 * stress))
            local flow = 0.5 + 0.5 * math.sin(vessel_phase[key] * 9 - time * (2 + 5 * stress))
            local flow_depth = 0.15 + 0.35 * stress
            strength = strength * throb * (1 - flow_depth + flow_depth * flow)
            color = mix(color, mix(VESSEL_FAINT, VESSEL_DARK, stress), (0.4 + 0.6 * stress) * strength)
        end
    end

    -- a small glint up and to the left of the pupil
    if (x == iris_x - 4 or x == iris_x - 3) and (y == iris_y - 5 or y == iris_y - 4) and to_iris > PUPIL_RADIUS then
        color = HIGHLIGHT
    end

    return color
end

-- Writes the whole picture for the current state of the eye into the shared image.
local function render(self)
    local openness = self.openness
    if self.blink_time > 0 then
        local progress = 1 - self.blink_time / BLINK_DURATION
        openness = openness * (1 - math.sin(math.pi * progress))
    end

    local time = love.timer.getTime()
    local is_closed = openness < CLOSED_BELOW
    local iris_x = CENTER_X + math.floor(self.look_x + 0.5)
    -- the iris sinks with the lowered slit (see get_open_color)
    local sink = math.floor(closed_droop[CENTER_X] * (1 - openness) ^ 2 + 0.5)
    local iris_y = CENTER_Y + math.floor(self.look_y + 0.5) + sink

    for y = 0, HEIGHT - 1 do
        for x = 0, WIDTH - 1 do
            local color
            if is_closed then
                color = get_closed_color(x, y)
            else
                color = get_open_color(x, y, openness, iris_x, iris_y, self.stress, time)
            end

            if color then
                image_data:setPixel(x, y, color[1], color[2], color[3], 1)
            else
                image_data:setPixel(x, y, 0, 0, 0, 0)
            end
        end
    end

    image:replacePixels(image_data)
end

-- Draws the eye centred at (screen_x, screen_y); every eye pixel is pixel_size screen pixels wide.
function eye.draw(self, screen_x, screen_y, pixel_size)
    prepare()
    render(self)

    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, screen_x - WIDTH * pixel_size / 2, screen_y - HEIGHT * pixel_size / 2, 0,
                       pixel_size, pixel_size)
end

return eye
