shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
void fragment() {
	float interior = smoothstep(0.0, 0.4, COLOR.r);
	ALBEDO = mix(vec3(0.09, 0.10, 0.08), vec3(0.04, 0.07, 0.08), interior);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.35, 0.12, interior);
	SPECULAR = 0.25;
	NORMAL_MAP = normalize(vec3(sin(UV.x * 43.0 + UV.y * 8.0 + TIME * 0.35) * 0.015, cos(UV.y * 51.0 + TIME * 0.25) * 0.015, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
}
