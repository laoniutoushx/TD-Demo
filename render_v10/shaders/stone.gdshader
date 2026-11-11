shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform vec3 base_tint : source_color = vec3(0.95, 0.97, 1.0);
uniform float normal_depth = 0.65;
uniform int style_mode = 0;
varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 c = texture(base_map, UV).rgb * base_tint;
	if (style_mode == 2) {
		c = mix(vec3(0.55, 0.54, 0.50), c, 0.35);
	}
	ALBEDO = c;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = style_mode == 2 ? 0.10 : (style_mode == 1 ? normal_depth * 0.75 : normal_depth);
	ROUGHNESS = clamp(0.65 + texture(orm_map, UV).g * 0.35, 0.65, 0.98);
	METALLIC = 0.0;
	SPECULAR = style_mode == 2 ? 0.08 : 0.25;

	// Soft base soil contact blending
	float dirt_mask = smoothstep(0.0, 1.0, clamp(1.0 - (world_position.y - 0.01) / 0.22, 0.0, 1.0));
	vec3 soil_color = vec3(0.18, 0.15, 0.11);
	ALBEDO = mix(ALBEDO, soil_color, dirt_mask * 0.68);
	ROUGHNESS = mix(ROUGHNESS, 0.95, dirt_mask);
}
