shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 20.0) = 3.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 0.5) = 0.15;
uniform bool enable_pulse = true;

void vertex() {
	vec4 clip_position = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 clip_normal = mat3(PROJECTION_MATRIX) * (mat3(MODELVIEW_MATRIX) * NORMAL);

	// 1. 防御除以零 NaN：法线近平面模长保护
	float norm_len = length(clip_normal.xy);
	vec2 norm_dir = vec2(0.0);
	if (norm_len > 0.0005) {
		norm_dir = clip_normal.xy / norm_len;
	}

	// 2. 呼吸微光脉冲
	float pulse = 1.0;
	if (enable_pulse) {
		pulse += sin(TIME * pulse_speed) * pulse_intensity;
	}

	// 3. 屏幕空间一致厚度偏移
	vec2 offset = norm_dir / VIEWPORT_SIZE * clip_position.w * outline_width * pulse * 2.0;
	clip_position.xy += offset;

	POSITION = clip_position;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}

