shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_front;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform sampler2D stencil_texture : filter_nearest;

uniform float cell_size = 2.0;
uniform float line_thickness = 0.045;
uniform vec4 grid_line_color : source_color = vec4(0.35, 0.85, 1.0, 0.45);
uniform vec4 default_inner_color : source_color = vec4(0.08, 0.25, 0.45, 0.03);

// 3态语义颜色（增强对比度与发光质感）
uniform vec4 buildable_color : source_color = vec4(0.20, 0.85, 0.52, 0.22); // 可建青绿微光
uniform vec4 occupied_color : source_color = vec4(0.95, 0.30, 0.15, 0.35);  // 占用琥珀红
uniform vec4 blocked_color : source_color = vec4(0.10, 0.12, 0.16, 0.06);   // 道路/不可建暗灰

uniform vec2 stencil_origin = vec2(0.0, 0.0);
uniform float stencil_world_size = 64.0;
uniform bool stencil_enabled = false;

uniform vec3 focus_pos = vec3(0.0, 0.0, 0.0);
uniform float visible_radius = 38.0;
uniform float fade_margin = 12.0;
uniform float grid_alpha = 1.0;

// 投影盒半尺寸（用于世界空间严格包围盒裁剪，杜绝 0.5 单位误裁剪）
uniform vec3 box_extents = vec3(70.0, 8.0, 70.0);

void fragment() {
    float depth = texture(depth_texture, SCREEN_UV).x;
    if (depth >= 1.0) {
        discard;
    }

    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);

    // 严格限制在投影 BoxMesh 范围内（支持 140m x 140m 等实际大尺寸）
    vec3 local_pos = (inverse(MODEL_MATRIX) * world).xyz;
    if (abs(local_pos.x) > box_extents.x || abs(local_pos.y) > box_extents.y || abs(local_pos.z) > box_extents.z) {
        discard;
    }

    // 基于世界坐标 X 与 Z 精确计算 2m 细分网格
    vec2 grid_uv = fract((world.xz + vec2(cell_size * 0.5)) / cell_size);
    vec2 border = abs(grid_uv - 0.5) * 2.0;
    float border_val = max(border.x, border.y);

    // 细致的抗锯齿边线 (2m 网格线)
    float line = smoothstep(1.0 - line_thickness, 1.0, border_val);

    // 四角定位刻度增强
    float corner_tick = smoothstep(0.85, 1.0, border.x) * smoothstep(0.85, 1.0, border.y);
    line = max(line, corner_tick * 0.65);

    // 距离光标焦点的径向衰减
    float dist = length(world.xz - focus_pos.xz);
    float radial_fade = 1.0 - smoothstep(visible_radius - fade_margin, visible_radius, dist);

    // 采样周围地块状态 (0=不可建, 1=可建, 2=占用)
    vec4 cell_tint = default_inner_color;
    vec4 line_tint = grid_line_color;

    if (stencil_enabled) {
        vec2 st_uv = (world.xz - stencil_origin) / stencil_world_size;
        if (st_uv.x >= 0.0 && st_uv.x <= 1.0 && st_uv.y >= 0.0 && st_uv.y <= 1.0) {
            float raw_val = texture(stencil_texture, st_uv).r;
            int state_val = int(round(raw_val * 255.0));

            if (state_val == 2) {
                // 已被建筑占用：琥珀红 + 45度警告斜纹
                float hatch = step(0.6, sin((world.x + world.z) * 5.0) * 0.5 + 0.5);
                cell_tint = occupied_color * (0.75 + hatch * 0.55);
                line_tint = vec4(1.0, 0.4, 0.2, 0.75);
            } else if (state_val == 1) {
                // 可建造空闲地块：清晰青绿微光 + 中心战术十字准星
                float center_dist = length(grid_uv - 0.5);
                float center_dot = 1.0 - smoothstep(0.04, 0.09, center_dist);
                // 十字微光准星
                vec2 cross_arm = step(abs(grid_uv - 0.5), vec2(0.015, 0.12)) + step(abs(grid_uv - 0.5), vec2(0.12, 0.015));
                float cross_mask = clamp(cross_arm.x + cross_arm.y, 0.0, 1.0);
                cell_tint = buildable_color + vec4(0.35, 0.95, 0.6, 0.25) * max(center_dot, cross_mask * 0.5);
                line_tint = vec4(0.3, 1.0, 0.65, 0.75);
            } else {
                // 不可建造地貌 / 道路：暗冷灰微弱指示
                cell_tint = blocked_color;
                line_tint = vec4(0.25, 0.35, 0.45, 0.25);
            }
        }
    }

    vec4 final_color = mix(cell_tint, line_tint, line);
    float final_a = final_color.a * radial_fade * grid_alpha;

    if (final_a <= 0.001) {
        discard;
    }

    ALBEDO = final_color.rgb;
    ALPHA = final_a;
}
