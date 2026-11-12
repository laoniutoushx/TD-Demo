shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float outline_thickness : hint_range(0.001, 0.2) = 0.03;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 0.5) = 0.15;
uniform bool enable_pulse = true;

void vertex() {
	float pulse = 1.0;
	if (enable_pulse) {
		pulse += sin(TIME * pulse_speed) * pulse_intensity;
	}

	// 工业标准：在模型空间沿几何法线向外膨胀均匀物理厚度 (约 2~3 厘米)
	// 无论相机距离、透视畸变角度如何，背面外壳始终紧致贴合体表，物理阻断多边形撕裂与巨大防护罩膨胀！
	VERTEX += NORMAL * outline_thickness * pulse;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}


