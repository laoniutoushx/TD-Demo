shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_front;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

uniform vec3 box_extents = vec3(22.0, 5.5, 22.0);
uniform float radius = 20.0;
uniform vec4 color : source_color = vec4(0.22, 0.95, 0.65, 1.0);
uniform float alpha_mult : hint_range(0.0, 1.0) = 1.0;
uniform float hdr_intensity : hint_range(0.5, 4.0) = 1.45;
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.45;
uniform float tick_speed : hint_range(-1.0, 1.0) = 0.08;

void fragment() {
	if (alpha_mult <= 0.001 || radius <= 0.05) {
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

	vec3 local_pos = (inverse(MODEL_MATRIX) * world).xyz;
	if (abs(local_pos.x) > box_extents.x || abs(local_pos.y) > box_extents.y || abs(local_pos.z) > box_extents.z) {
		discard;
	}

	float r = length(local_pos.xz);
	if (r > radius + 0.75) {
		discard;
	}

	// 过滤垂直墙体、塔身侧面与单位躯干，仅投影贴合地形、道路与斜坡地表
	vec3 dpdx = dFdx(world.xyz);
	vec3 dpdy = dFdy(world.xyz);
	vec3 surf_n = normalize(cross(dpdy, dpdx) + vec3(1e-6));
	float slope_mask = smoothstep(0.48, 0.72, abs(surf_n.y));
	float height_mask = 1.0 - smoothstep(0.85, 1.65, local_pos.y);
	float surface_mask = slope_mask * height_mask;
	if (surface_mask <= 0.001) {
		discard;
	}

	// 世界空间亚像素抗锯齿步宽
	float px = max(fwidth(r), 0.015);
	float rim_half_w = max(0.055, px * 1.45);

	// 1. 主边界锐利光环 + 柔和外溢光晕
	float dist_outer = abs(r - radius);
	float primary_ring = 1.0 - smoothstep(rim_half_w, rim_half_w + px * 1.5, dist_outer);
	float outer_halo = exp(-dist_outer * 2.6) * 0.40 * (1.0 - smoothstep(radius + 0.15, radius + 0.70, r));

	// 2. 次级旋转刻度虚线环 (内缩 0.55m)
	float angle = atan(local_pos.z, local_pos.x);
	float inner_ring_r = max(0.25, radius - 0.55);
	float dist_inner = abs(r - inner_ring_r);
	float tick_pattern = smoothstep(0.15, 0.42, sin((angle + TIME * tick_speed) * 48.0));
	float inner_ring = (1.0 - smoothstep(0.028, 0.028 + px * 1.35, dist_inner)) * tick_pattern * 0.62;

	// 3. 四象限战术弧线角标 (外扩 0.18m)
	float bracket_r = radius + 0.18;
	float dist_bracket = abs(r - bracket_r);
	float quad_mask = smoothstep(0.84, 0.93, abs(cos(angle * 2.0 + TIME * tick_speed * 0.4)));
	float bracket_arc = (1.0 - smoothstep(0.045, 0.045 + px * 1.4, dist_bracket)) * quad_mask * 0.85;

	// 4. 径向内部微光填充 + 外扩雷达扫描波
	float inside_mask = 1.0 - smoothstep(radius - px, radius + px, r);
	float norm_r = clamp(r / max(radius, 0.1), 0.0, 1.0);
	float interior_fill = mix(0.012, 0.085, pow(norm_r, 2.4)) * inside_mask;

	float sweep_phase = fract(TIME * pulse_speed);
	float sweep_wave = exp(-abs(norm_r - sweep_phase) * 20.0) * (1.0 - sweep_phase) * 0.22 * inside_mask;

	float core_alpha = max(primary_ring, max(inner_ring, bracket_arc));
	float glow_alpha = outer_halo + interior_fill + sweep_wave;
	float final_alpha = clamp((core_alpha + glow_alpha) * surface_mask * alpha_mult, 0.0, 1.0);

	if (final_alpha <= 0.001) {
		discard;
	}

	vec3 core_rgb = mix(color.rgb, vec3(1.0), 0.35) * hdr_intensity;
	vec3 fill_rgb = color.rgb * 0.9;
	vec3 final_rgb = mix(fill_rgb, core_rgb, clamp(core_alpha * 1.15, 0.0, 1.0));

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}
