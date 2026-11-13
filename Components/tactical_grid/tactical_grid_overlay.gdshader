shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_front;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform float cell_size = 4.0;
uniform float line_thickness = 0.05;
uniform vec4 grid_color : source_color = vec4(0.28, 0.78, 1.0, 0.55);
uniform vec4 inner_color : source_color = vec4(0.08, 0.28, 0.48, 0.08);
uniform vec3 focus_pos = vec3(0.0, 0.0, 0.0);
uniform float visible_radius = 42.0;
uniform float fade_margin = 14.0;
uniform float grid_alpha = 1.0;

void fragment() {
    float depth = texture(depth_texture, SCREEN_UV).x;
    // 过滤背景无几何体的区域（远裁切面）
    if (depth >= 1.0) {
        discard;
    }

    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);

    // 验证当前深度重建点是否在投影 BoxMesh 的 Y 轴范围内（避免无上限上下穿透）
    vec3 local_pos = (inverse(MODEL_MATRIX) * world).xyz;
    if (abs(local_pos.y) > 0.5 || abs(local_pos.x) > 0.5 || abs(local_pos.z) > 0.5) {
        discard;
    }

    // 基于世界坐标 X 与 Z 精确计算 4m 网格（带 0.5 偏移对齐单元格中心）
    vec2 grid_uv = fract((world.xz + vec2(cell_size * 0.5)) / cell_size);
    vec2 border = abs(grid_uv - 0.5) * 2.0;
    float border_val = max(border.x, border.y);

    // 细致的抗锯齿边线
    float line = smoothstep(1.0 - line_thickness, 1.0, border_val);

    // 四角定位刻度增强（Corner Ticks）
    float corner_tick = smoothstep(0.85, 1.0, border.x) * smoothstep(0.85, 1.0, border.y);
    line = max(line, corner_tick * 0.8);

    // 距离光标/英雄焦点的径向衰减（Radial Falloff）
    float dist = length(world.xz - focus_pos.xz);
    float radial_fade = 1.0 - smoothstep(visible_radius - fade_margin, visible_radius, dist);

    vec4 col = mix(inner_color, grid_color, line);
    float final_a = col.a * radial_fade * grid_alpha;

    if (final_a <= 0.001) {
        discard;
    }

    ALBEDO = col.rgb;
    ALPHA = final_a;
}
