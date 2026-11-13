shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 2.0;

uniform sampler2D main_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dissolve_noise : filter_linear_mipmap, repeat_enable;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width : hint_range(0.0, 0.4) = 0.08;
uniform vec4 edge_color : source_color = vec4(2.5, 1.5, 0.5, 1.0);

uniform vec2 uv_scroll_speed = vec2(0.0, 0.0);
uniform float uv_scale = 1.0;

uniform bool use_soft_depth = true;
uniform float soft_depth_fade : hint_range(0.01, 2.0) = 0.25;
uniform sampler2D depth_texture_sampler : hint_depth_texture;

void fragment() {
	vec2 uv = UV * uv_scale + uv_scroll_speed * TIME;
	vec4 tex = texture(main_texture, uv);
	float noise = texture(dissolve_noise, uv).r;

	// Calculate erosion edge
	float d = noise - dissolve_amount;
	if (d < 0.0) {
		discard;
	}

	float edge = 1.0 - smoothstep(0.0, edge_width, d);
	vec3 final_color = mix(tex.rgb * albedo_color.rgb, edge_color.rgb, edge);

	float alpha = tex.a * albedo_color.a * (1.0 - dissolve_amount);

	// Soft particle depth fade
	if (use_soft_depth) {
		float depth_tex = textureLod(depth_texture_sampler, SCREEN_UV, 0.0).r;
		vec4 world_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth_tex, 1.0);
		world_pos.xyz /= world_pos.w;
		float contact = clamp(abs(world_pos.z - VERTEX.z) / soft_depth_fade, 0.0, 1.0);
		alpha *= contact;
	}

	ALBEDO = final_color;
	EMISSION = final_color * emission_energy;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
