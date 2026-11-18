shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(3.8, 4.8, 6.5, 1.0);
uniform vec4 glow_color : source_color = vec4(0.25, 0.78, 3.6, 1.0);
uniform float emission_energy : hint_range(0.5, 12.0) = 3.2;
uniform float bolt_width : hint_range(0.02, 2.0) = 0.34;

uniform float arc_length : hint_range(0.1, 100.0) = 5.0;
uniform float uv_scroll_speed : hint_range(-20.0, 20.0) = 6.0;
uniform float leader_progress : hint_range(0.0, 1.3) = 1.2;
uniform float intensity : hint_range(0.0, 2.5) = 1.0;
uniform float clock = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise12(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void vertex() {
	// VERTEX stores centerline point; NORMAL stores local tangent; UV2.x = side (-1/+1), UV2.y = width scale.
	mat3 model_3x3 = mat3(MODEL_MATRIX);
	vec3 world_center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 world_tangent = model_3x3 * NORMAL;
	float t_len = length(world_tangent);
	world_tangent = t_len > 1e-5 ? (world_tangent / t_len) : vec3(0.0, 0.0, 1.0);

	vec3 to_cam = CAMERA_POSITION_WORLD - world_center;
	float c_len = length(to_cam);
	to_cam = c_len > 1e-5 ? (to_cam / c_len) : vec3(0.0, 1.0, 0.0);

	vec3 world_side = cross(world_tangent, to_cam);
	float s_len = length(world_side);
	if (s_len < 1e-4) {
		world_side = cross(world_tangent, vec3(0.0, 1.0, 0.0));
		s_len = length(world_side);
		if (s_len < 1e-4) {
			world_side = vec3(1.0, 0.0, 0.0);
			s_len = 1.0;
		}
	}
	world_side /= s_len;

	float half_w = bolt_width * 0.5 * UV2.y;
	vec3 world_offset = world_side * (UV2.x * half_w);
	if (abs(determinant(model_3x3)) > 1e-6) {
		VERTEX += inverse(model_3x3) * world_offset;
	}
}

void fragment() {
	float cross_dist = abs(UV.y * 2.0 - 1.0);

	// Tight incandescent core + high-contrast corona falloff
	float core = exp(-cross_dist * cross_dist * 40.0);
	float inner_corona = exp(-cross_dist * 5.2);
	float outer_halo = pow(clamp(1.0 - cross_dist, 0.0, 1.0), 2.4);

	// World-space plasma density & traveling electrical pulse knots along the channel
	float coord_x = UV.x * max(arc_length, 1.0) * 1.45 - clock * uv_scroll_speed;
	float plasma = 0.62 + 0.58 * noise12(vec2(coord_x, floor(clock * 26.0) * 0.37));
	float travel_knot = 0.78 + 0.42 * pow(0.5 + 0.5 * sin(coord_x * 2.4), 3.0);
	float micro_pinch = 0.8 + 0.38 * noise12(vec2(coord_x * 3.2, clock * 16.0));
	float core_mod = core * mix(0.88, 1.28, micro_pinch) * travel_knot;

	// Leader wave propagation from caster (UV.x = 0) to target (UV.x = 1)
	float leader_mask = 1.0 - smoothstep(max(leader_progress - 0.08, 0.0), leader_progress + 0.02, UV.x);
	float leader_tip = exp(-pow((UV.x - leader_progress) * 14.0, 2.0)) * step(leader_progress, 1.05);

	vec3 bolt_tint = mix(glow_color.rgb, COLOR.rgb * glow_color.rgb, 0.55);
	vec3 final_color = (
		core_color.rgb * (core_mod * 1.65 + leader_tip * 0.95 * inner_corona) +
		bolt_tint * (inner_corona * 0.92 + outer_halo * 0.36) * plasma
	) * emission_energy * intensity * leader_mask * COLOR.a;

	float alpha = clamp((core_mod * 1.35 + inner_corona * 0.8 + outer_halo * 0.35) * leader_mask * COLOR.a * intensity, 0.0, 1.0);

	ALBEDO = final_color;
	EMISSION = final_color;
	ALPHA = alpha;
}
