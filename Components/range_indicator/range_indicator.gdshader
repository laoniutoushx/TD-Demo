shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_front;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

instance uniform float radius = 10.0;
instance uniform vec4 color : source_color = vec4(0.22, 0.95, 0.65, 1.0);
instance uniform float alpha_mult = 1.0;
instance uniform float style_mode = 0.0; // 0.0 = 攻击范围/预览, 1.0 = 技能释放范围

const float HDR_INTENSITY = 1.45;
const float PULSE_SPEED = 0.28;
const float TICK_SPEED = 0.08;

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

	// 直接计算世界空间偏移，免去每像素 4x4 inverse(MODEL_MATRIX)
	vec3 rel = world.xyz - MODEL_MATRIX[3].xyz;
	float r = length(rel.xz);
	if (r > radius + 0.75 || abs(rel.y) > 5.0) {
		discard;
	}

	// 过滤垂直墙体、塔身侧面与单位躯干，仅投影贴合地形、道路与斜坡地表
	vec3 dpdx = dFdx(world.xyz);
	vec3 dpdy = dFdy(world.xyz);
	vec3 surf_n = normalize(cross(dpdy, dpdx) + vec3(1e-6));
	float slope_mask = smoothstep(0.48, 0.72, abs(surf_n.y));
	float height_mask = 1.0 - smoothstep(0.85, 1.65, rel.y);
	float surface_mask = slope_mask * height_mask;
	if (surface_mask <= 0.001) {
		discard;
	}

	// 世界空间亚像素抗锯齿步宽
	float px = max(fwidth(r), 0.015);
	float rim_half_w = max(0.055, px * 1.45);

	float is_skill = step(0.5, style_mode);

	// 1. 主边界锐利光环 + 柔和外溢光晕
	float dist_outer = abs(r - radius);
	float ring_w = mix(rim_half_w, rim_half_w * 1.15, is_skill);
	float primary_ring = 1.0 - smoothstep(ring_w, ring_w + px * 1.5, dist_outer);
	float outer_halo = exp(-dist_outer * 2.8) * mix(0.30, 0.42, is_skill) * (1.0 - smoothstep(radius + 0.15, radius + 0.65, r));

	// 2. 四象限战术弧线角标 (技能模式略微增强并加快旋转以明确区别于攻击范围)
	vec2 dir = rel.xz / max(r, 0.0001);
	float cos2 = dir.x * dir.x - dir.y * dir.y;
	float sin2 = 2.0 * dir.x * dir.y;
	float qt = TIME * TICK_SPEED * mix(0.35, 1.35, is_skill);
	float quad_cos = abs(cos2 * cos(qt) - sin2 * sin(qt));
	float quad_mask = smoothstep(mix(0.84, 0.76, is_skill), mix(0.93, 0.88, is_skill), quad_cos);
	float bracket_r = radius + mix(0.18, 0.24, is_skill);
	float bracket_arc = (1.0 - smoothstep(0.045, 0.045 + px * 1.4, abs(r - bracket_r))) * quad_mask * mix(0.65, 0.95, is_skill);

	// 3. 次级刻度虚线环 - 攻击范围静谧微弱，技能范围使用清晰醒目的旋转施法刻度环
	float inner_offset = mix(0.55, 0.40, is_skill);
	float inner_ring_r = max(0.25, radius - inner_offset);
	float dist_inner = abs(r - inner_ring_r);
	float inner_ring = 0.0;
	if (dist_inner < 0.2) {
		float angle = atan(rel.z, rel.x);
		float seg_freq = mix(48.0, 24.0, is_skill);
		float seg_speed = mix(TICK_SPEED, -TICK_SPEED * 3.0, is_skill);
		float tick_pattern = smoothstep(mix(0.18, 0.05, is_skill), mix(0.44, 0.30, is_skill), sin((angle + TIME * seg_speed) * seg_freq));
		inner_ring = (1.0 - smoothstep(mix(0.025, 0.038, is_skill), mix(0.025, 0.038, is_skill) + px * 1.35, dist_inner)) * tick_pattern * mix(0.42, 0.82, is_skill);
	}

	// 4. 径向内部微光填充 + 极弱化的外扩波纹 (避免喧宾夺主分散玩家对战斗单位的注意力)
	float inside_mask = 1.0 - smoothstep(radius - px, radius + px, r);
	float norm_r = clamp(r / max(radius, 0.1), 0.0, 1.0);
	float interior_fill = mix(0.004, mix(0.048, 0.065, is_skill), pow(norm_r, 2.8)) * inside_mask;

	float sweep_phase = fract(TIME * PULSE_SPEED);
	float sweep_edge_bias = smoothstep(0.25, 0.85, norm_r);
	float sweep_strength = mix(0.028, 0.045, is_skill);
	float sweep_wave = exp(-abs(norm_r - sweep_phase) * 16.0) * (1.0 - sweep_phase) * sweep_edge_bias * sweep_strength * inside_mask;

	float core_alpha = max(primary_ring, max(inner_ring, bracket_arc));
	float glow_alpha = outer_halo + interior_fill + sweep_wave;
	float final_alpha = clamp((core_alpha + glow_alpha) * surface_mask * alpha_mult, 0.0, 1.0);

	if (final_alpha <= 0.001) {
		discard;
	}

	float hdr = mix(1.25, HDR_INTENSITY, is_skill);
	vec3 core_rgb = mix(color.rgb, vec3(1.0), mix(0.28, 0.42, is_skill)) * hdr;
	vec3 fill_rgb = color.rgb * mix(0.82, 0.95, is_skill);
	vec3 final_rgb = mix(fill_rgb, core_rgb, clamp(core_alpha * 1.15, 0.0, 1.0));

	ALBEDO = final_rgb;
	ALPHA = final_alpha;
}
