shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform vec4 hologram_color : source_color = vec4(0.2, 0.85, 0.6, 0.75);
uniform float scanline_speed : hint_range(0.0, 10.0) = 3.0;
uniform float scanline_frequency : hint_range(1.0, 100.0) = 30.0;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.2;
uniform float emission_strength : hint_range(0.0, 5.0) = 1.2;

void fragment() {
	// 视线边缘发光 (Fresnel)
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndotv, fresnel_power);
	
	// 垂直扫描波纹 (Scanlines)
	float scanline = sin((VERTEX.y - TIME * scanline_speed) * scanline_frequency) * 0.5 + 0.5;
	
	// 全息颜色与自发光
	ALBEDO = hologram_color.rgb;
	EMISSION = hologram_color.rgb * (fresnel * 1.8 + scanline * 0.5) * emission_strength;
	
	// 透明度综合计算：边缘更清晰，中间微透，扫描线微亮
	float alpha_val = hologram_color.a * (0.35 + fresnel * 0.65 + scanline * 0.15);
	ALPHA = clamp(alpha_val, 0.0, 0.95);
}
