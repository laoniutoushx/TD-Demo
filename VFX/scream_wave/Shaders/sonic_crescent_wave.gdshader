shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.80, 0.84, 1.0);
uniform vec4 mid_color : source_color = vec4(0.92, 0.09, 0.24, 1.0);
uniform vec4 edge_color : source_color = vec4(0.18, 0.03, 0.20, 1.0);
uniform float emission_strength : hint_range(0.0, 12.0) = 4.2;
uniform float density : hint_range(0.0, 2.0) = 1.0;
uniform float progress : hint_range(0.0, 1.0) = 0.25;
uniform float life_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float proximity_fade_distance : hint_range(0.01, 2.5) = 0.40;
uniform float scroll_speed : hint_range(0.1, 6.0) = 2.6;
uniform float turbulence_strength : hint_range(0.0, 1.0) = 0.35;

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D streak_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

void fragment() {
	// UV.x: 0.0 (left wingtip) .. 0.5 (apex center) .. 1.0 (right wingtip)
	// UV.y: 0.0 (sharp leading Mach crest) .. 1.0 (trailing shock wake tail)
	float arc_u = UV.x;
	float wake_v = UV.y;

	// Taper wingtips cleanly
	float arc_envelope = sin(clamp(arc_u, 0.0, 1.0) * PI);
	arc_envelope = pow(max(arc_envelope, 0.0), 0.72);

	// Dual-octave supersonic shear streaks + serrated acoustic Mach interference ribs
	float t = TIME * scroll_speed;
	vec2 streak_uv = vec2(arc_u * 5.5, wake_v * 1.6 - t * 0.72);
	vec2 turb_uv = vec2(arc_u * 3.8 + sin(wake_v * 7.5 - t) * 0.09, wake_v * 2.5 - t * 1.05);
	float n_streak = texture(streak_tex, streak_uv).r;
	float n_turb = texture(noise_tex, turb_uv).r;
	float shear = mix(n_streak, n_turb, 0.42);

	// Warped leading & trailing silhouette with high-frequency jagged shock ridges
	float v_warped = clamp(wake_v + (n_turb - 0.5) * turbulence_strength * (0.25 + wake_v), 0.0, 1.0);
	float mach_ribs = pow(0.5 + 0.5 * sin(v_warped * 24.0 - t * 2.5 + n_streak * 4.5), 2.2) * (1.0 - v_warped);

	// Razor-sharp Mach compression front line (high-energy core near v ~ 0.02..0.10)
	float front_in = smoothstep(0.0, 0.045, v_warped);
	float crest_band = front_in * exp(-max(v_warped - 0.038, 0.0) * 20.0);

	// Violent shredded mid-wave shock curtain with dark obsidian compression veins
	float tail_fade = 1.0 - smoothstep(0.24, 0.97 - (1.0 - shear) * 0.36, v_warped);
	float body_mask = front_in * tail_fade * (0.52 + 0.72 * shear + 0.35 * mach_ribs);

	// High-contrast dark obsidian acoustic fracture bands inside wake
	float fracture = smoothstep(0.28, 0.68, n_streak * 0.62 + n_turb * 0.38 + mach_ribs * 0.25);

	// Soft ground/obstacle proximity fade
	float depth_raw = texture(depth_tex, SCREEN_UV).x;
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	view_pos.xyz /= view_pos.w;
	float depth_diff = max(0.0, (-view_pos.z) - (-VERTEX.z));
	float prox_fade = clamp(depth_diff / max(proximity_fade_distance, 0.001), 0.0, 1.0);

	// Fresnel silhouette accent along curved shell
	float ndotv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), 1.45);

	// Color composition: deep obsidian violet void -> blood-crimson shock ribs -> white-hot Mach crest
	vec3 wake_col = mix(edge_color.rgb * 0.65, mid_color.rgb, clamp(fracture * 0.95 + mach_ribs * 0.45, 0.0, 1.0));
	wake_col *= (0.78 + 0.72 * fresnel);
	vec3 hdr_crest = core_color.rgb * emission_strength * (0.8 + 0.65 * n_turb);
	vec3 final_col = mix(wake_col, hdr_crest, clamp(crest_band * 1.45 + mach_ribs * 0.22 * (1.0 - v_warped), 0.0, 1.0));

	float alpha = (body_mask * 0.90 + crest_band) * arc_envelope * prox_fade * life_alpha * density;
	ALBEDO = final_col * (1.0 + crest_band * 0.95);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
