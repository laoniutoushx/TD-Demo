shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_front;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

instance uniform float radius = 1.8;
instance uniform vec4 color : source_color = vec4(0.24, 0.92, 0.58, 0.95);

const float HDR_INTENSITY = 1.32;
const float ORBIT_SPEED = 0.42;

void fragment() {
	if (radius <= 0.05 || color.a <= 0.001) {
		discard;
	}

	float depth = texture(depth_texture, SCREEN_UV).x;
	if (depth >= 1.0) {
		discard;
	}

	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);

	// 直接基于模型原点计算世界偏移，避免每像素 4x4 inverse(MODEL_MATRIX) 矩阵求逆
	vec3 rel = world.xyz - MODEL_MATRIX[3].xyz;
	float r = length(rel.xz);
	float max_r = radius * 1.12;
	if (r > max_r || abs(rel.y) > 1.8) {
		discard;
	}

	// 仅贴合地表、道路、路缘与地基裙边，过滤垂直墙体与单位躯干
	vec3 dpdx = dFdx(world.xyz);
	vec3 dpdy = dFdy(world.xyz);
	vec3 surf_n = normalize(cross(dpdy, dpdx) + vec3(1e-6));
	float slope_mask = smoothstep(0.50, 0.74, abs(surf_n.y));
	float height_mask = 1.0 - smoothstep(0.45, 1.05, rel.y);
	float surface_mask = slope_mask * height_mask;
	if (surface_mask <= 0.001) {
		discard;
	}

	float px = max(fwidth(r), 0.01);
	float main_r = radius * 0.88;
	float arc_r = radius * 0.97;
	float inner_r = radius * 0.74;

	// 1. 主聚焦细环（亚像素抗锯齿 + 极克制微光晕）
	float dist_main = abs(r - main_r);
	float main_half_w = clamp(radius * 0.022, 0.028, 0.055);
	float main_ring = 1.0 - smoothstep(main_half_w, main_half_w + px * 1.35, dist_main);
	float soft_halo = exp(-dist_main * 8.5) * 0.24 * (1.0 - smoothstep(main_r + 0.08, max_r, r));

	// 2. 双对称悬浮轨道弧（倍角恒等式旋转，无 atan() 三角超越函数开销）
	vec2 dir = rel.xz / max(r, 0.0001);
	float cos2 = dir.x * dir.x - dir.y * dir.y;
	float sin2 = 2.0 * dir.x * dir.y;
	float phase_t = TIME * ORBIT_SPEED;
	float arc_phase = cos2 * cos(phase_t) + sin2 * sin(phase_t);
	float arc_mask = smoothstep(0.42, 0.56, arc_phase);
	float dist_arc = abs(r - arc_r);
	float arc_half_w = clamp(radius * 0.014, 0.018, 0.034);
	float orbit_arcs = (1.0 - smoothstep(arc_half_w, arc_half_w + px * 1.3, dist_arc)) * arc_mask * 0.82;

	// 3. 极简内圈发丝线 + 低饱和脚底氛围底色
	float dist_inner = abs(r - inner_r);
	float inner_line = (1.0 - smoothstep(0.012, 0.012 + px * 1.3, dist_inner)) * 0.24;
	float norm_r = clamp(r / max(main_r, 0.05), 0.0, 1.0);
	float inside_mask = 1.0 - smoothstep(main_r - px, main_r + px, r);
	float base_tint = mix(0.01, 0.085, pow(norm_r, 2.2)) * inside_mask;

	float line_alpha = max(main_ring, max(orbit_arcs, inner_line));
	float final_alpha = clamp((line_alpha + soft_halo + base_tint) * color.a * surface_mask, 0.0, 1.0);

	if (final_alpha <= 0.001) {
		discard;
	}

	vec3 highlight_rgb = mix(color.rgb, vec3(1.0), 0.38) * HDR_INTENSITY;
	vec3 ambient_rgb = color.rgb * 0.85;
	vec3 final_rgb = mix(ambient_rgb, highlight_rgb, clamp(line_alpha * 1.1, 0.0, 1.0));

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}
