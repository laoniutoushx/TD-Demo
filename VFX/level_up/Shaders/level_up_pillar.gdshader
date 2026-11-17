shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded;

uniform vec4 core_color : source_color = vec4(1.0, 0.78, 0.30, 1.0);
uniform vec4 rim_color : source_color = vec4(0.45, 0.88, 1.0, 1.0);
uniform float emission_strength : hint_range(0.0, 8.0) = 2.6;
uniform float progress : hint_range(0.0, 1.0) = 0.25;
uniform float fresnel_power : hint_range(0.5, 6.0) = 1.75;
uniform float proximity_fade_distance : hint_range(0.01, 2.5) = 0.35;
uniform vec2 uv_scale = vec2(2.0, 1.0);
uniform vec2 scroll_speed_primary = vec2(0.32, 1.45);
uniform vec2 scroll_speed_secondary = vec2(-0.48, 2.25);

uniform sampler2D energy_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D streak_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

void fragment() {
	// CylinderMesh side UV.y: 0.0 at top, 1.0 at bottom -> invert to 0.0 (bottom) .. 1.0 (top)
	float h = clamp(1.0 - UV.y, 0.0, 1.0);

	// Dual-octave upward flowing energy streaks
	vec2 base_uv = vec2(UV.x * uv_scale.x, h * uv_scale.y);
	float t = TIME;
	float n1 = texture(energy_texture, base_uv + scroll_speed_primary * t).r;
	float n2 = texture(streak_texture, base_uv * vec2(1.5, 1.2) + scroll_speed_secondary * t).r;
	float streaks = mix(n1, n1 * n2 * 1.65, 0.65);

	// Vertical lifecycle envelope: fast rise from ground, smooth upward dissipation
	float reveal_top = smoothstep(0.0, 0.28, progress);
	float dissolve_bottom = smoothstep(0.42, 0.96, progress);
	float top_gate = 1.0 - smoothstep(reveal_top * 1.15 - 0.18, reveal_top * 1.15 + 0.04, h);
	float bottom_gate = smoothstep(dissolve_bottom * 1.15 - 0.22, dissolve_bottom * 1.15 + 0.04, h);
	float life_fade = smoothstep(0.0, 0.08, progress) * (1.0 - smoothstep(0.72, 1.0, progress));

	// Soft vertical boundaries so cylinder caps never show hard edges
	float edge_v = smoothstep(0.0, 0.14, h) * smoothstep(1.0, 0.28, h);

	// Fresnel rim highlights cylindrical silhouette
	float ndotv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), fresnel_power);
	float rim_mix = clamp(fresnel * 0.85 + 0.15, 0.0, 1.0);

	// Soft ground/mesh intersection proximity fade
	float depth_raw = texture(depth_texture, SCREEN_UV).x;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view_pos.xyz /= view_pos.w;
	float depth_diff = max(0.0, (-view_pos.z) - (-VERTEX.z));
	float prox_fade = clamp(depth_diff / max(proximity_fade_distance, 0.001), 0.0, 1.0);

	float alpha = streaks * top_gate * bottom_gate * edge_v * life_fade * prox_fade * (0.35 + 0.65 * rim_mix);
	vec3 col = mix(core_color.rgb, rim_color.rgb, fresnel * 0.65 + h * 0.25);

	ALBEDO = col * emission_strength * (0.7 + 0.8 * streaks);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
