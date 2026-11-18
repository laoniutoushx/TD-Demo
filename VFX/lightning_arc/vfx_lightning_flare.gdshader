shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform vec4 core_color : source_color = vec4(3.8, 4.8, 6.5, 1.0);
uniform vec4 glow_color : source_color = vec4(0.25, 0.78, 3.6, 1.0);
uniform float emission_energy : hint_range(0.5, 12.0) = 3.2;
uniform float intensity : hint_range(0.0, 2.5) = 1.0;
uniform float clock = 0.0;

void vertex() {
	// Camera-facing billboard quad preserving local scale
	mat4 mv = VIEW_MATRIX * MODEL_MATRIX;
	float sx = length(vec3(MODEL_MATRIX[0].xyz));
	float sy = length(vec3(MODEL_MATRIX[1].xyz));
	mv[0] = vec4(sx, 0.0, 0.0, 0.0);
	mv[1] = vec4(0.0, sy, 0.0, 0.0);
	mv[2] = vec4(0.0, 0.0, 1.0, 0.0);
	MODELVIEW_MATRIX = mv;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);
	float angle = atan(centered.y, centered.x);
	float rays = 0.78 + 0.22 * sin(angle * 6.0 + clock * 18.0) * sin(angle * 4.0 - clock * 13.0);

	float core = exp(-r * r * 14.0);
	float corona = exp(-r * 3.8) * rays * smoothstep(1.0, 0.25, r);

	vec3 col = (core_color.rgb * core + glow_color.rgb * corona * 0.9) * emission_energy * intensity;
	float alpha = clamp((core + corona * 0.75) * intensity, 0.0, 1.0);

	ALBEDO = col;
	EMISSION = col;
	ALPHA = alpha;
}
