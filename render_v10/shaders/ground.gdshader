shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D soil_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D noise_map : filter_linear_mipmap, repeat_enable;
uniform float normal_strength = 0.22;
uniform sampler2D forest_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float layered = 1.0;
uniform sampler2D road_distance_map : filter_linear, repeat_disable;
uniform vec4 map_bounds = vec4(-136.0, -88.0, 272.0, 176.0);
uniform int style_mode = 0;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float macro = texture(noise_map, p * 0.065).r;
	float micro = texture(noise_map, p * 0.3).r;
	vec2 rotated = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p;
	vec3 soil = mix(texture(soil_map, p * 0.18).rgb, texture(soil_map, rotated * 0.143 + vec2(0.37, 0.71)).rgb, smoothstep(0.3, 0.7, macro));
	
	// Natural 5-zone distance transition
	vec2 map_uv = clamp((p - map_bounds.xy) / map_bounds.zw, vec2(0.0), vec2(1.0));
	vec2 ecology = texture(road_distance_map, map_uv).rg;
	float road_dist = ecology.r * 25.0;
	float broken_edge = road_dist + (macro - 0.5) * 1.1;

	// Zone 1: Road edge moss strip (1.2m to 2.4m)
	float edge_moss = smoothstep(1.1, 1.45, broken_edge) * (1.0 - smoothstep(1.7, 2.5, broken_edge));
	// General patchy moss based on macro noise
	float patch_moss = smoothstep(0.50, 0.76, macro + micro * 0.18) * smoothstep(1.5, 4.5, road_dist);
	float moss = clamp((edge_moss * 0.85 + patch_moss * 0.45), 0.0, 0.85);

	soil = mix(vec3(dot(soil, vec3(0.2126, 0.7152, 0.0722))), soil, style_mode == 2 ? 0.35 : 0.75);
	vec3 dirt = soil * mix(vec3(0.94, 0.95, 0.94), vec3(1.02, 1.02, 1.0), macro);
	
	// Base albedo: mix dirt and lush moss
	float meadow = smoothstep(1.6, 2.8, broken_edge) * (1.0 - ecology.g * 0.7);
	float grass_patch = smoothstep(0.28, 0.65, macro * 0.7 + micro * 0.3);
	vec3 meadow_color = soil * vec3(0.52, 1.05, 0.28);
	ALBEDO = mix(dirt * vec3(0.85, 0.88, 0.78), meadow_color, meadow * mix(0.38, 0.88, grass_patch));
	// Small dry flecks and exposed earth break the mown meadow into quiet patches.
	ALBEDO = mix(ALBEDO, soil * vec3(0.90, 0.84, 0.61), meadow * smoothstep(0.72, 0.85, micro) * 0.28);
	ALBEDO = mix(ALBEDO, soil * vec3(0.40, 0.62, 0.20), moss);

	// Zone 4: Forest litter layer (starts at 5.5m out, deep under tree canopies)
	float litter = smoothstep(0.02, 0.65, ecology.g) * smoothstep(1.5, 2.5, road_dist) * (0.65 + 0.35 * smoothstep(0.2, 0.7, micro)) * layered;
	
	NORMAL_MAP = texture(soil_normal, p * 0.18).rgb;
	NORMAL_MAP = mix(NORMAL_MAP, texture(soil_normal, p * 1.6).rgb, 0.15);
	NORMAL_MAP_DEPTH = style_mode == 2 ? 0.04 : (style_mode == 1 ? normal_strength : normal_strength * 1.35);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.77, 0.98, micro);

	vec2 forest_dx = dFdx(p * 0.46), forest_dy = dFdy(p * 0.46);
	if (litter > 0.001 && style_mode != 2) {
		vec3 forest = textureGrad(forest_map, p * 0.46, forest_dx, forest_dy).rgb;
		ALBEDO = mix(ALBEDO, forest * vec3(0.90, 1.02, 0.92), litter);
		NORMAL_MAP = mix(NORMAL_MAP, textureGrad(forest_normal, p * 0.46, forest_dx, forest_dy).rgb, litter * 0.65);
		ROUGHNESS = mix(ROUGHNESS, textureGrad(forest_rough, p * 0.46, forest_dx, forest_dy).r, litter * 0.5);
	}
	ALBEDO *= 0.88;
}
