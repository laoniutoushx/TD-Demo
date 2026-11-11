shader_type spatial;
render_mode cull_disabled;
#include "res://asset_lab/benchmark/materials/leaf_common.gdshaderinc"

void light() {
	// Style 2: Top-Down Gameplay — crisp quantized cel-bands + graphic dome contour separation
	float ndl = dot(NORMAL, LIGHT);
	float half_l = ndl * 0.5 + 0.5;
	float score = half_l * mix(0.28, 1.0, ATTENUATION) * 0.54 + v_palette_grad * 0.28 + v_spatial_ao * 0.24 - 0.05;

	// Use source_color uniforms (already in linear space) with a cool teal shift in shadows
	vec3 cel_core   = col_core_shadow * vec3(0.75, 0.95, 1.25);
	vec3 cel_shadow = col_dark_forest * vec3(0.82, 1.02, 1.28);
	vec3 cel_mid    = col_mid_green   * vec3(0.92, 1.06, 0.95);
	vec3 cel_lit    = col_warm_sunlit * vec3(1.02, 1.05, 0.92);
	vec3 cel_rim    = col_bright_tip;

	vec3 band_col = cel_core;
	band_col = mix(band_col, cel_shadow, smoothstep(0.24, 0.255, score));
	band_col = mix(band_col, cel_mid,    smoothstep(0.46, 0.475, score));
	band_col = mix(band_col, cel_lit,    smoothstep(0.68, 0.695, score));
	band_col = mix(band_col, cel_rim,    smoothstep(0.85, 0.865, score));

	// Graphic dome contour / inner-cavity ink line for unmistakable top-down silhouette separation
	float ndv = abs(dot(NORMAL, VIEW));
	float contour_ink = smoothstep(0.36, 0.14, ndv) * smoothstep(0.86, 0.30, score);
	band_col = mix(band_col, cel_core * 0.45, contour_ink * 0.72);

	// Crisp stepped top-edge rim highlight on sunlit side
	float fresnel = 1.0 - ndv;
	float rim_step = step(0.66, fresnel * smoothstep(0.0, 0.5, ndl) * ATTENUATION);
	band_col = mix(band_col, cel_rim, rim_step * 0.42);

	vec3 color_ratio = band_col / max(ALBEDO, vec3(0.012));
	vec3 light_norm = clamp(LIGHT_COLOR / PI, vec3(0.0), vec3(1.08));
	DIFFUSE_LIGHT += color_ratio * 0.76 * light_norm;
}
