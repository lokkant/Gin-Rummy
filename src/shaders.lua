-- All GLSL shaders, compiled once when this module is required (client only: needs love.graphics).
-- They are globals: dragging_card_shader, hovered_card_shader, card_shader, highlight_card_shader,
-- highlight_hovered_card_shader and lamp_shader.
-- Card shaders use `uv`, the texture coordinate in 0..1 over the whole card image, so their effects scale
-- with the card. `time` is love.timer.getTime(), sent by the caller every frame before drawing.

local love = require "love"

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

-- Round turn lamp. It is drawn onto a stretched 1x1 white image (see client/hud.lua), so the picture
-- carries no information and everything comes from the texture coordinates. is_on is 0 or 1.
lamp_shader = love.graphics.newShader([[
extern number time;
extern number is_on;
extern vec3 lamp_color;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
    // Map the texture coordinates 0..1 to -1..1, so the lamp centre is (0, 0).
    vec2 uv = texture_coords * 2.0 - 1.0;
    // dist: distance from the centre; 1 at the middle of the quad's edges.
    float dist = length(uv);

    // Gentle pulse between 0.7 and 1.0.
    float pulse = 0.85 + 0.15 * sin(time * 1.0);

    // body: solid disc of radius about 0.36 with a soft edge.
    float body = 1.0 - smoothstep(0.32, 0.4, dist);
    // glow: halo that fades out towards the quad border, only visible when the lamp is on.
    float glow = (1.0 - smoothstep(0.35, 1.0, dist)) * is_on * pulse;
    // highlight: small bright spot up and left of the centre that gives the lamp a glassy look.
    float highlight = (1.0 - smoothstep(0.0, 0.22, length(uv - vec2(-0.12, -0.16)))) * is_on;

    // Dull brown when off, the pulsing lamp colour when on.
    vec3 offColor = vec3(0.22, 0.18, 0.14);
    vec3 onColor = lamp_color * pulse;

    // is_on selects between the two colours; the highlight spot adds a little white.
    vec3 col = mix(offColor, onColor, is_on) + highlight * 0.6;
    // The glow is half transparent, the body is opaque.
    float alpha = clamp(body + glow * 0.5, 0.0, 1.0);

    return vec4(col, alpha) * color;
}
]])
