shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 core_color : source_color = vec4(2.5, 3.0, 4.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.4, 1.2, 3.5, 1.0);
uniform float emission_energy : hint_range(1.0, 10.0) = 3.0;

uniform float noise_speed : hint_range(1.0, 60.0) = 28.0;
uniform float frequency : hint_range(1.0, 20.0) = 6.0;
uniform float amplitude : hint_range(0.01, 0.4) = 0.12;
uniform float arc_length : hint_range(0.1, 100.0) = 4.0;
uniform float world_tiling : hint_range(0.1, 5.0) = 1.0;
uniform float uv_scroll_speed : hint_range(-20.0, 20.0) = 1.5;
uniform float fade_alpha : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	// UV.x runs along length [0, 1], UV.y runs across width [0, 1]
	float t = floor(TIME * noise_speed);
	float length_scale = max(arc_length * world_tiling * 0.25, 0.5);
	float sample_x = UV.x * frequency * length_scale - TIME * uv_scroll_speed * 0.15;
	float displacement = (noise(vec2(sample_x, t)) - 0.5) * amplitude;
	displacement += (noise(vec2(sample_x * 2.5, t + 43.0)) - 0.5) * (amplitude * 0.4);

	// Center line distance
	float dist = abs((UV.y - 0.5) - displacement);

	// Core bolt and outer electrical glow
	float core = smoothstep(0.04, 0.0, dist);
	float glow = smoothstep(0.35, 0.0, dist);

	// End fade
	float end_fade = sin(UV.x * PI);

	vec3 color = (core_color.rgb * core + glow_color.rgb * glow) * emission_energy * fade_alpha;
	float alpha = clamp((core * 1.5 + glow * 0.7) * end_fade * COLOR.a * fade_alpha, 0.0, 1.0);

	ALBEDO = color;
	EMISSION = color;
	ALPHA = alpha;
}
