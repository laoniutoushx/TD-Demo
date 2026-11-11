shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://asset_lab/benchmark/materials/leaf_common.gdshaderinc"

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ndl_clamped = max(ndl, 0.0);

	if (style_mode == 0) {
		// Style 0: Realistic PBR — physically-based direct + subsurface translucency + crisp micro-specular
		// Note: Godot multiplies DIFFUSE_LIGHT by ALBEDO automatically after light()
		float cavity = mix(0.25, 1.12, v_spatial_ao);
		float sss = pow(clamp(dot(-NORMAL, LIGHT), 0.0, 1.0), 1.8) * ATTENUATION * v_tip_weight * 0.38;
		vec3 sss_ratio = vec3(1.35, 1.55, 0.65) * sss;
		DIFFUSE_LIGHT += ( vec3(ndl_clamped * cavity) + sss_ratio ) * ATTENUATION * LIGHT_COLOR / PI;

		vec3 H = normalize(LIGHT + VIEW);
		float ndh = max(dot(NORMAL, H), 0.0);
		float spec = pow(ndh, 26.0) * ndl_clamped * ATTENUATION * v_spatial_ao;
		SPECULAR_LIGHT += spec * 0.24 * LIGHT_COLOR / PI;
	} else {
		// Style 1: Hand-Painted PBR — artistic 5-stop painterly gradient with controlled highlights
		float half_l = ndl * 0.5 + 0.5;
		float lit_factor = half_l * mix(0.28, 1.0, ATTENUATION);
		float palette_pos = clamp(lit_factor * 0.54 + v_palette_grad * 0.26 + v_spatial_ao * 0.24 - 0.06, 0.04, 0.92);
		vec3 target_col = sample_5stop_palette(palette_pos) * mix(1.0, v_detail_mod, 0.36);

		// Cool teal-green shift in deep shadow vs warm golden-green on sunlit crown
		vec3 cool_shadow_tint = vec3(0.11, 0.26, 0.16);
		target_col = mix(cool_shadow_tint, target_col, smoothstep(0.08, 0.48, palette_pos));

		// Subtle warm rim translucency on backlit clump edges
		float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.6) * smoothstep(-0.15, 0.65, dot(-LIGHT, NORMAL)) * ATTENUATION;
		target_col = mix(target_col, col_bright_tip, clamp(rim * 0.28 * v_tip_weight, 0.0, 0.32));

		// Divide by ALBEDO without double-multiplying energy so output matches exact 5-stop palette
		vec3 color_ratio = target_col / max(ALBEDO, vec3(0.012));
		vec3 light_norm = clamp(LIGHT_COLOR / PI, vec3(0.0), vec3(1.08));
		DIFFUSE_LIGHT += color_ratio * 0.78 * light_norm;

		vec3 H = normalize(LIGHT + VIEW);
		float ndh = max(dot(NORMAL, H), 0.0);
		float spec = pow(ndh, 14.0) * ndl_clamped * ATTENUATION * v_spatial_ao;
		SPECULAR_LIGHT += spec * 0.06 * light_norm;
	}
}
