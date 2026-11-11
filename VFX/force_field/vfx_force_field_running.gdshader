shader_type spatial;
render_mode cull_back, shadows_disabled, depth_draw_never;

uniform sampler2D grid_sampler : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture_sampler : hint_depth_texture;
uniform vec3 base_color : source_color;
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0; // Added transparency parameter

float fresnel(float amount, vec3 normal, vec3 view) {
    return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0 )), amount);
}

void vertex() {
    float wave = ((1.0 + sin((UV.y + TIME * 0.1) * PI * 4.0)) * 0.5);
    VERTEX += NORMAL * wave * 0.01;
}

void fragment() {
    float depth_texture = textureLod(depth_texture_sampler, SCREEN_UV, 0.0).r;
    vec4 world_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0,depth_texture, 1.0);
    world_pos.xyz /= world_pos.w;

    float rim = fresnel(4.0, NORMAL, VIEW);
    float contact = 1.0 - smoothstep(0.0, 0.12, abs(world_pos.z - VERTEX.z));
    float height_mask = smoothstep(0.8, 1.0, sin(UV.y * PI));
    vec2 hex_color = texture(grid_sampler, (UV + vec2(0.0, TIME * 0.01)) * vec2(2.0, 1.0) * 2.0).xy;
    float hex_edge = hex_color.x * height_mask;
    float hex_fill = smoothstep(0.01, 0.0,
        (sin(hex_color.y * 10.0 + TIME * 0.1) + 1.0) * 0.5) * height_mask * (1.0 - hex_color.x);
    float wave = step(sin((UV.y + TIME * 0.04) * 8.0 * PI), 0.0);

    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
    ALBEDO = base_color;
    // Clear centers remain readable when many active shields overlap. The
    // silhouette, contact edge and moving grid still communicate the buff.
    EMISSION = base_color * (0.45 + rim * 0.75 + contact * 0.25);
    ALPHA = clamp(0.012 + rim * 0.28 + contact * 0.14
        + hex_edge * 0.035 + hex_fill * 0.018 + wave * 0.008, 0.0, 0.45) * alpha_value;
}
