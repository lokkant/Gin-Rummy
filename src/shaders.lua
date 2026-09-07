local love = require "love"

dragging_card_shader = love.graphics.newShader([[
extern number time;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen_coords)
{
    vec4 pixel = Texel(tex, uv);

    float cycle = mod(time, 2.0);

    float fadeIn  = smoothstep(0.0, 0.35, cycle);
    float fadeOut = 1.0 - smoothstep(1.4, 1.8, cycle);
    float shineTime = fadeIn * fadeOut;

    float center = mix(-0.25, 1.25, cycle / 1.8);
    float diagonal = uv.x + uv.y * 0.35;

    float distance = abs(diagonal - center);
    float shine = 1.0 - smoothstep(0.0, 0.16, distance);

    shine *= shineTime;

    vec3 shineColor = vec3(1., 1., 1.);

    pixel.rgb = mix(
        pixel.rgb,
        shineColor,
        shine * 0.65
    );

    float edge = smoothstep(0.0, 0.25, distance);
    pixel.rgb -= shine * edge * 0.04;

    return pixel * color;
}
]])

hovered_card_shader = dragging_card_shader

card_shader = love.graphics.newShader([[
extern number time;

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen_coords)
{
    vec2 p = uv * 180.0;

    float n = fract(
        sin(dot(floor(p), vec2(127.1, 311.7)))
        * 43758.5453123
    );

    vec2 p2 = uv * 360.0;
    float n2 = fract(
        sin(dot(floor(p2), vec2(269.5, 183.3)))
        * 43758.5453123
    );

    float noise = mix(n, n2, 0.35);

    float animation = sin(time * 1.5 + noise * 6.28318) * 0.5 + 0.5;

    float amount = mix(-0.025, 0.025, animation);

    vec4 tex = Texel(texture, uv);

    return vec4(
        tex.rgb + amount,
        tex.a
    );
}
]])

highlight_card_shader = love.graphics.newShader([[
extern number time;
extern vec3 highlight_color;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screenPos)
{
    vec4 base = Texel(tex, uv) * color;

    float edge = min(
        min(uv.x, 1.0 - uv.x),
        min(uv.y, 1.0 - uv.y)
    );

    float edgeGlow = 1.0 - smoothstep(0.0, 0.03, edge);
    float rim = 1.0 - smoothstep(0.0, 0.01, edge);

    float pulse = 0.85 + 0.15 * sin(time * 3.0);

    vec3 tinted = mix(
        base.rgb,
        highlight_color,
        edgeGlow * 0.8 * pulse
    );

    return vec4(tinted, base.a);
}
]])


lamp_shader = love.graphics.newShader([[
extern number time;
extern number is_on;
extern vec3 lamp_color;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords)
{
    vec2 uv = texture_coords * 2.0 - 1.0;
    float dist = length(uv);

    float pulse = 0.85 + 0.15 * sin(time * 1.0);

    float body = 1.0 - smoothstep(0.32, 0.4, dist);
    float glow = (1.0 - smoothstep(0.35, 1.0, dist)) * is_on * pulse;
    float highlight = (1.0 - smoothstep(0.0, 0.22, length(uv - vec2(-0.12, -0.16)))) * is_on;

    vec3 offColor = vec3(0.22, 0.18, 0.14);
    vec3 onColor = lamp_color * pulse;

    vec3 col = mix(offColor, onColor, is_on) + highlight * 0.6;
    float alpha = clamp(body + glow * 0.5, 0.0, 1.0);

    return vec4(col, alpha) * color;
}
]])


return dragging_card_shader, hovered_card_shader, card_shader, highlight_card_shader, lamp_shader