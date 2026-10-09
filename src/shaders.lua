-- All GLSL shaders, compiled once when this module is required (client only: needs love.graphics).
-- They are globals: dragging_card_shader, hovered_card_shader, card_shader, highlight_card_shader,
-- highlight_hovered_card_shader and spotlight_shader.
-- Card shaders use `uv`, the texture coordinate in 0..1 over the whole card image, so their effects scale
-- with the card. `time` is love.timer.getTime(), sent by the caller every frame before drawing.

local love = require "love"

-- Outline colours (RGB) of the 1st, 2nd and 3rd meld of a hand: blue, green, red. Three are enough because
-- 11 cards hold at most three melds. Used with highlight_card_shader for the player's and the revealed
-- opponent's hand.
combination_colors = {{0.0, 0.0, 1.0}, {0.0, 1.0, 0.0}, {1.0, 0.0, 0.0}}

-- Shine sweep for the card being dragged: a soft white diagonal band crosses the card every 2 seconds.
dragging_card_shader = love.graphics.newShader([[
// time: seconds, set from Lua every frame.
extern number time;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 pixel = Texel(tex, uv);

    // A 2 s cycle: the band travels for the first 1.8 s, the rest is a pause.
    float cycle = mod(time, 2.0);

    // shineTime fades the band in during the first 0.35 s and out between 1.4 s and 1.8 s.
    float fadeIn  = smoothstep(0.0, 0.35, cycle);
    float fadeOut = 1.0 - smoothstep(1.4, 1.8, cycle);
    float shineTime = fadeIn * fadeOut;

    // Centre of the band along the diagonal axis: from just left of the card (-0.25) to just right (1.25).
    float center = mix(-0.25, 1.25, cycle / 1.8);
    // Diagonal coordinate; the 0.35 share of y tilts the band slightly.
    float diagonal = uv.x + uv.y * 0.35;

    // Distance of this pixel from the band's centre line; shine is 1 on the line and 0 beyond 0.16.
    float distance = abs(diagonal - center);
    float shine = 1.0 - smoothstep(0.0, 0.16, distance);

    // Fade the band in and out over the cycle.
    shine *= shineTime;

    vec3 shineColor = vec3(1., 1., 1.);

    // Blend towards white by up to 65 %.
    pixel.rgb = mix(
        pixel.rgb,
        shineColor,
        shine * 0.65
    );

    // Darken the outer rim of the band by at most 4 %, so the band looks glossy instead of flat.
    float edge = smoothstep(0.0, 0.25, distance);
    pixel.rgb -= shine * edge * 0.04;

    // Multiplying by `color` keeps the tint and alpha set with love.graphics.setColor.
    return pixel * color;
}
]])

-- Dragging and hovering use the same shine.
hovered_card_shader = dragging_card_shader

-- Subtle shimmer of ordinary cards: every cell of the texture gets its own pseudo-random phase, so the
-- brightness of the surface flickers by +-0.025 and the card looks slightly alive.
card_shader = love.graphics.newShader([[
extern number time;

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_coords)
{
    // Two noise grids over the card: 180 x 180 and 360 x 360 cells (different hash constants).
    vec2 p = uv * 180.0;

    // Classic one-line hash: a pseudo-random number in 0..1 for each cell (the constants are the usual
    // magic numbers of this hash, only their irregularity matters).
    float n = fract(
        sin(dot(floor(p), vec2(127.1, 311.7)))
        * 43758.5453123
    );

    vec2 p2 = uv * 360.0;
    float n2 = fract(
        sin(dot(floor(p2), vec2(269.5, 183.3)))
        * 43758.5453123
    );

    // The coarse and the fine layer are mixed 65 / 35.
    float noise = mix(n, n2, 0.35);

    // Every cell oscillates with its own phase (noise * 2*pi = 6.28318); animation is in 0..1.
    float animation = sin(time * 1.5 + noise * 6.28318) * 0.5 + 0.5;

    // Brightness offset of -0.025..+0.025, added to every colour channel.
    float amount = mix(-0.025, 0.025, animation);

    // Alpha is kept, so the rounded corners stay transparent.
    vec4 tex = Texel(texture, uv);

    return vec4(
        tex.rgb + amount,
        tex.a
    );
}
]])

-- Pulsing outline in `highlight_color` for cards that belong to a meld (one colour per meld).
highlight_card_shader = love.graphics.newShader([[
extern number time;
extern vec3 highlight_color;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screenPos)
{
    vec4 base = Texel(tex, uv) * color;

    // edge: distance of this pixel to the nearest card border in uv units (0 on the border itself).
    float edge = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );

    // edgeGlow: 1 on the border, falling to 0 within 3 % of the card size.
    float edgeGlow = 1.0 - smoothstep(0.0, 0.03, edge);

    // Pulse between 0.7 and 1.0, repeating about every 2 s.
    float pulse = 0.85 + 0.15 * sin(time * 3.0);

    // Mix the outline colour into the border pixels, at most 80 %, so the card art stays readable.
    vec3 tinted = mix(
        base.rgb,
        highlight_color,
        edgeGlow * 0.8 * pulse
    );

    // The original alpha is kept.
    return vec4(tinted, base.a);
}
]])

-- Outline of highlight_card_shader plus the shine of dragging_card_shader, for a hovered or dragged card
-- that is part of a meld.
highlight_hovered_card_shader = love.graphics.newShader([[
extern number time;
extern vec3 highlight_color;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 pixel = Texel(tex, uv);

    // combination outline (same as highlight_card_shader)
    float edge = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );

    float edgeGlow = 1.0 - smoothstep(0.0, 0.03, edge);
    float pulse = 0.85 + 0.15 * sin(time * 3.0);

    pixel.rgb = mix(
        pixel.rgb,
        highlight_color,
        edgeGlow * 0.8 * pulse
    );

    // shine (same as dragging_card_shader)
    float cycle = mod(time, 2.0);

    float fadeIn  = smoothstep(0.0, 0.35, cycle);
    float fadeOut = 1.0 - smoothstep(1.4, 1.8, cycle);
    float shineTime = fadeIn * fadeOut;

    float center = mix(-0.25, 1.25, cycle / 1.8);
    float diagonal = uv.x + uv.y * 0.35;

    float distance = abs(diagonal - center);
    float shine = 1.0 - smoothstep(0.0, 0.16, distance);

    shine *= shineTime;

    pixel.rgb = mix(
        pixel.rgb,
        vec3(1., 1., 1.),
        shine * 0.65
    );

    float shineEdge = smoothstep(0.0, 0.25, distance);
    pixel.rgb -= shine * shineEdge * 0.04;

    return pixel * color;
}
]])

-- The table felt with a light over the half of the active player. It is drawn onto a stretched 1x1 white
-- image that covers the window (see client/hud.lua), so the picture carries no information and everything
-- comes from the texture coordinates. The lit half is bright and warm, the other half is darker and covered
-- with a fine checker pattern, so the difference does not rely on colour alone.
spotlight_shader = love.graphics.newShader([[
// time: seconds, set from Lua every frame (the light breathes a little).
extern number time;
// felt_color: the plain table colour, RGB 0..1.
extern vec3 felt_color;
// light_y: vertical position of the light centre, 0 = top edge, 1 = bottom edge; Lua moves it smoothly
// between the opponent's and the player's side.
extern number light_y;
// strength: 0 = flat felt (nobody's turn), 1 = the full effect; also changed smoothly from Lua.
extern number strength;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
    // Elliptical light: wide horizontally and tall enough to reach past the middle of the table, so the
    // stock and the discard pile stay readable for both players. d is 1 at the edge of the ellipse.
    vec2 p = (texture_coords - vec2(0.5, light_y)) / vec2(0.85, 0.62);
    float d = length(p);

    // lit: 1 in the centre of the light, 0 outside the ellipse; a slow +-4 % breathing.
    float lit = (1.0 - smoothstep(0.15, 1.0, d)) * (0.96 + 0.04 * sin(time * 1.5));

    // Brightness from 0.6 (unlit) to 1.1 (lit) and a little warm yellow in the lit area.
    float brightness = mix(0.6, 1.1, lit);
    vec3 col = felt_color * brightness + vec3(0.07, 0.05, 0.0) * lit;

    // Checker of 3x3 pixels that darkens the unlit area a bit more (dither).
    float checker = mod(floor(screen_coords.x / 3.0) + floor(screen_coords.y / 3.0), 2.0);
    col *= 1.0 - 0.07 * (1.0 - lit) * checker;

    // strength fades the whole effect in and out.
    col = mix(felt_color, col, strength);

    return vec4(col, 1.0) * color;
}
]])
