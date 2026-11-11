shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 tint : source_color = vec3(0.90, 0.93, 0.98);
uniform vec4 wet_centers[4];
uniform sampler2D rune_map : hint_default_black, filter_linear_mipmap_anisotropic;
uniform float rune_enabled = 0.0;
uniform bool rune_geometry = false;
uniform float road_gain = 0.86;
uniform float water_enabled = 0.0;
uniform bool has_wet = false;
uniform bool has_baked_reflection = false;
uniform samplerCube water_reflection : source_color, filter_linear_mipmap;
uniform float reflection_energy = 1.0;
uniform int style_mode = 1;
varying vec3 world_pos;
varying float top_face;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	top_face = smoothstep(0.65, 0.95, NORMAL.y);
}

void fragment() {
	float wet = 0.0;
	float water = 0.0;
	if (has_wet) {
		for (int i = 0; i < 4; i++) {
			if (wet_centers[i].z < 0.5) {
				continue;
			}
			vec2 p = world_pos.xz - wet_centers[i].xy;
			if (max(abs(p.x), abs(p.y)) > 0.52) {
				continue;
			}
			float r = length(p / vec2(0.32, 0.37));
			float angle = atan(p.y, p.x);
			r /= 1.0 + 0.13 * sin(angle * 2.0 + float(i) * 0.7) + 0.09 * sin(angle * 3.0 + 1.1 + float(i) * 0.2) + 0.045 * cos(angle * 7.0 + 0.9);
			wet = max(wet, (1.0 - smoothstep(0.90, 1.25, r)) * wet_centers[i].z);
			water = max(water, (1.0 - smoothstep(0.90, 1.00, r)) * wet_centers[i].z);
		}
	}
	wet *= top_face;
	water *= top_face * water_enabled;
	vec3 tex_col = texture(base_map, UV).rgb;
	if (style_mode == 2) {
		tex_col = mix(vec3(dot(tex_col, vec3(0.2126, 0.7152, 0.0722))), tex_col, 0.25);
		tex_col = mix(vec3(0.66, 0.65, 0.60), tex_col, 0.35);
	}
	vec3 stone = tex_col * tint * COLOR.rgb * road_gain;
	float stone_luma = dot(stone, vec3(0.2126, 0.7152, 0.0722));
	stone = mix(vec3(stone_luma), stone, 0.45) * vec3(0.96, 0.99, 1.03);
	ALBEDO = stone * mix(1.0, 0.76, wet);
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = style_mode == 2 ? 0.08 : (style_mode == 1 ? 0.20 : 0.32);
	if (rune_enabled > 0.5) {
		float h = texture(rune_map, UV).r;
		vec2 ray = vec2(dot(VIEW, TANGENT), dot(VIEW, BINORMAL)) / max(dot(VIEW, NORMAL), 0.25);
		vec2 uv = UV - ray * h * 0.006;
		h = texture(rune_map, uv).r;
		float e = 1.0 / 2048.0;
		vec2 slope = vec2(texture(rune_map, uv - vec2(e, 0)).r - texture(rune_map, uv + vec2(e, 0)).r, texture(rune_map, uv - vec2(0, e)).r - texture(rune_map, uv + vec2(0, e)).r);
		NORMAL_MAP = normalize((NORMAL_MAP * 2.0 - 1.0) + vec3(slope * (rune_geometry ? 0.20 : 0.65), 0)) * 0.5 + 0.5;
		ALBEDO *= 1.0 - h * 0.22;
	}
	ALBEDO = mix(ALBEDO, stone * vec3(0.48, 0.58, 0.53), water);
	if (water > 0.001) {
		vec3 ripple = normalize(vec3(sin(world_pos.x * 31.0 + world_pos.z * 11.0 + TIME * 0.35) * 0.025, cos(world_pos.z * 37.0 - world_pos.x * 9.0 + TIME * 0.25) * 0.025, 1.0)) * 0.5 + 0.5;
		NORMAL_MAP = mix(NORMAL_MAP, ripple, water);
	}
	NORMAL_MAP_DEPTH = mix(NORMAL_MAP_DEPTH, 0.65, water);
	ROUGHNESS = mix(clamp(texture(rough_map, UV).r * 0.85, 0.46, 0.91), 0.24, wet);
	ROUGHNESS = mix(ROUGHNESS, 0.06, water);
	METALLIC = 0.0;
	SPECULAR = mix(style_mode == 2 ? 0.08 : 0.28, 0.50, water);
	RADIANCE = vec4(0.0);
	if (has_baked_reflection && water > 0.001) {
		vec3 eye = normalize(INV_VIEW_MATRIX[3].xyz - world_pos);
		vec3 water_normal = normalize(vec3(sin(world_pos.x * 31.0 + TIME * 0.35) * 0.018, 1.0, cos(world_pos.z * 37.0 + TIME * 0.25) * 0.018));
		vec3 reflected = reflect(-eye, water_normal);
		RADIANCE = vec4(textureLod(water_reflection, reflected, 0.65).rgb * reflection_energy, water);
	}
}
