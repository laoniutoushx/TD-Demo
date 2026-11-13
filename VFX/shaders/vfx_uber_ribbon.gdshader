shader_type spatial;
render_mode particle_trails, blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 trail_color : source_color = vec4(1.0, 1.4, 2.2, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 2.5;
uniform sampler2D trail_texture : hint_default_white, source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 uv_scroll = vec2(0.0, -2.0);
uniform bool length_along_y = true;
uniform float head_fade : hint_range(0.0, 0.5) = 0.05;
uniform float tail_fade : hint_range(0.5, 1.0) = 0.85;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform float depth_fade_distance : hint_range(0.0, 5.0) = 0.5;

void fragment() {
	vec2 uv = UV + uv_scroll * TIME;
	vec4 tex = texture(trail_texture, uv);

	float length_coord = length_along_y ? UV.y : UV.x;
	float width_coord = length_along_y ? UV.x : UV.y;

	// Length-wise fade (head fade-in, tail fade-out)
	float fade = smoothstep(0.0, max(head_fade, 0.001), length_coord) * (1.0 - smoothstep(min(tail_fade, 0.999), 1.0, length_coord));
	
	// Cross-width edge fade
	float edge = sin(clamp(width_coord, 0.0, 1.0) * PI);

	float alpha = tex.a * trail_color.a * fade * edge * COLOR.a;
	vec3 color = tex.rgb * trail_color.rgb * COLOR.rgb;

	// Soft depth fade near ground or obstacles
	if (depth_fade_distance > 0.0) {
		float depth = texture(depth_texture, SCREEN_UV).r;
		vec4 upos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		vec3 pixel_position = upos.xyz / upos.w;
		float scene_depth = -pixel_position.z;
		float object_depth = -VERTEX.z;
		float depth_diff = clamp((scene_depth - object_depth) / depth_fade_distance, 0.0, 1.0);
		alpha *= depth_diff;
	}

	ALBEDO = color;
	EMISSION = color * emission_energy;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
