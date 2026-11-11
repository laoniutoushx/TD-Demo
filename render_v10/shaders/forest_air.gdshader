shader_type fog;
void fog() {
	vec3 edge = smoothstep(vec3(0.0), vec3(0.22), UVW) * (1.0 - smoothstep(vec3(0.78), vec3(1.0), UVW));
	float lower = mix(0.4, 1.0, smoothstep(0.25, 1.2, WORLD_POSITION.y));
	float upper = 1.0 - smoothstep(3.5, 7.5, WORLD_POSITION.y);
	DENSITY = 0.009 * edge.x * edge.y * edge.z * lower * upper;
	ALBEDO = vec3(0.94, 0.96, 1.0);
}
