shader_type spatial;
render_mode cull_back, unshaded, depth_draw_never, shadows_disabled;

uniform float distortion_strength : hint_range(0.0, 0.15) = 0.04;
uniform float rim_power : hint_range(0.5, 6.0) = 3.0;
uniform vec4 rim_color : source_color = vec4(1.2, 1.5, 2.0, 1.0);
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

float fresnel(float amount, vec3 normal, vec3 view) {
	return pow((1.0 - clamp(dot(normalize(normal), normalize(view)), 0.0, 1.0)), amount);
}

void fragment() {
	vec2 noise = (texture(noise_texture, UV + TIME * 0.2).xy * 2.0 - 1.0) * distortion_strength;
	vec3 refracted_screen = texture(screen_texture, SCREEN_UV + noise).rgb;

	float rim = fresnel(rim_power, NORMAL, VIEW);
	vec3 final_color = refracted_screen + rim_color.rgb * rim * COLOR.rgb;

	ALBEDO = final_color;
	ALPHA = clamp(COLOR.a * (0.8 + rim * 0.5), 0.0, 1.0);
}
