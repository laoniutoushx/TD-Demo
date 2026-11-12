shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(0.2, 0.85, 1.0, 1.0);
uniform float outline_thickness : hint_range(0.001, 0.2) = 0.035;
uniform float pulse_speed : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_intensity : hint_range(0.0, 0.5) = 0.15;
uniform bool enable_pulse = true;
uniform bool distance_adaptive = true;

void vertex() {
	float pulse = 1.0;
	if (enable_pulse) {
		pulse += sin(TIME * pulse_speed) * pulse_intensity;
	}

	// 工业级世界缩放归一化：反解节点层级在世界空间中的绝对缩放比例
	// 彻底抹平不同模型导入管线 (FBX 100x/0.01x, GLTF 0.02455x/1.0x) 的巨大尺度差异！
	vec3 world_scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	world_scale = max(world_scale, vec3(0.00001));

	float thickness = outline_thickness;
	if (distance_adaptive) {
		// 计算顶点至相机距离（View Space 顶点坐标模长）
		float cam_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
		// RTS 视角下基准距离约为 35米，采用轻量线性插值，平滑限制在 [0.7, 1.6] 区间
		// 近景（10米内）保持约 2.5~3cm，远景（40~50米）自适应放大至约 4~5cm（保证屏幕上约 1.5~2 像素边界）
		float dist_factor = clamp(cam_dist / 35.0, 0.7, 1.6);
		thickness *= dist_factor;
	}

	// 统一物理厚度挤出：在世界空间严格恒等于 thickness * pulse (米)
	VERTEX += (NORMAL / world_scale) * thickness * pulse;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}



