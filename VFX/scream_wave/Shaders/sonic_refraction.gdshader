shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform float distortion_strength : hint_range(0.0, 0.12) = 0.032;
uniform float chromatic_split : hint_range(0.0, 0.025) = 0.0045;
uniform float scroll_speed : hint_range(0.1, 6.0) = 3.2;
uniform float life_alpha : hint_range(0.0, 1.0) = 1.0;
uniform float rim_power : hint_range(0.5, 6.0) = 2.4;
uniform vec4 tint_color : source_color = vec4(0.95, 0.25, 0.45, 1.0);

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

void fragment() {
	float arc_env = pow(max(sin(clamp(UV.x, 0.0, 1.0) * PI), 0.0), 0.85);
	float wake_env = sin(clamp(UV.y, 0.0, 1.0) * PI);
	float mask = arc_env * wake_env * life_alpha;

	float t = TIME * scroll_speed;
	vec2 n_uv1 = vec2(UV.x * 3.5, UV.y * 2.0 - t * 0.7);
	vec2 n_uv2 = vec2(UV.x * 5.0 + 0.3, UV.y * 2.6 - t * 1.05);
	float nx = texture(noise_tex, n_uv1).r * 2.0 - 1.0;
	float ny = texture(noise_tex, n_uv2).r * 2.0 - 1.0;

	vec2 offset = vec2(nx, ny * 0.65) * distortion_strength * mask;
	vec2 base_uv = clamp(SCREEN_UV + offset, vec2(0.002), vec2(0.998));
	vec2 split_uv_r = clamp(base_uv + offset * (chromatic_split / max(distortion_strength, 0.0001)), vec2(0.002), vec2(0.998));
	vec2 split_uv_b = clamp(base_uv - offset * (chromatic_split / max(distortion_strength, 0.0001)), vec2(0.002), vec2(0.998));

	float r = texture(screen_tex, split_uv_r).r;
	float g = texture(screen_tex, base_uv).g;
	float b = texture(screen_tex, split_uv_b).b;
	vec3 refracted = vec3(r, g, b);

	float ndotv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fresnel = pow(clamp(1.0 - ndotv, 0.0, 1.0), rim_power);
	vec3 final_col = refracted + tint_color.rgb * fresnel * 0.45 * mask;

	ALBEDO = final_col;
	ALPHA = clamp(mask * 0.92, 0.0, 1.0);
}
