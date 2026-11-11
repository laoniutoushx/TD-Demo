shader_type spatial;
render_mode cull_disabled, diffuse_burley;
varying vec3 meadow_tint;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float lock_tip = smoothstep(0.015, 0.14, VERTEX.y);
	VERTEX.x += sin(TIME * 1.4 + dot(origin.xz, vec2(0.71,0.37))) * 0.018 * lock_tip;
	meadow_tint = INSTANCE_CUSTOM.rgb;
}
void fragment() {
	ALBEDO = COLOR.rgb * meadow_tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.12;
	BACKLIGHT = ALBEDO * 0.18;
	if (!FRONT_FACING) NORMAL = -NORMAL;
}
