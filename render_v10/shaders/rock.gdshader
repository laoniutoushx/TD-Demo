shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
varying vec3 local_position;
varying vec3 world_normal;
varying vec3 world_position;

void vertex() {
	local_position = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
float noise3(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = dot(i, vec3(1.0, 57.0, 113.0));
	vec4 a = fract(sin(vec4(n, n + 1.0, n + 57.0, n + 58.0)) * 43758.5453);
	vec4 b = fract(sin(vec4(n + 113.0, n + 114.0, n + 170.0, n + 171.0)) * 43758.5453);
	return mix(mix(mix(a.x, a.y, f.x), mix(a.z, a.w, f.x), f.y), mix(mix(b.x, b.y, f.x), mix(b.z, b.w, f.x), f.z), f.z);
}
void fragment() {
	float n_macro = noise3(local_position * 7.5);
	float n_micro = noise3(local_position * 64.0);
	float variation = 0.84 + 0.22 * n_macro + 0.06 * n_micro;
	vec3 slate_stone = vec3(0.32, 0.34, 0.36) * variation;
	vec3 moss_tint = vec3(0.20, 0.31, 0.19) * (0.85 + 0.25 * n_macro);
	float moss_mask = smoothstep(0.55, 0.86, world_normal.y + (n_macro - 0.5) * 0.32);
	ALBEDO = mix(slate_stone, moss_tint, moss_mask * 0.68);
	ROUGHNESS = mix(0.84, 0.92, moss_mask);
	
	// Soft object-ground contact boundary blending
	float dirt_mask = smoothstep(0.0, 1.0, clamp(1.0 - (world_position.y - 0.01) / 0.20, 0.0, 1.0));
	vec3 soil_color = vec3(0.18, 0.15, 0.11) * (0.85 + 0.30 * n_macro);
	ALBEDO = mix(ALBEDO, soil_color, dirt_mask * 0.72);
	ROUGHNESS = mix(ROUGHNESS, 0.95, dirt_mask);
	
	SPECULAR = 0.20;
}
