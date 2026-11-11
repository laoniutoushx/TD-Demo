shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap;
uniform int orm_roughness_channel = 1;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform bool cutout = false;
uniform bool is_combined_mesh = false;
uniform int style = 1; // 1 = Hand-Painted PBR, 2 = Top-Down Gameplay

// Concept Sheet 5-Stop Broadleaf Palette (sRGB source_color)
uniform vec3 foliage_core_color   : source_color = vec3(0.094, 0.173, 0.078); // #182C14
uniform vec3 foliage_shadow_color : source_color = vec3(0.184, 0.325, 0.114); // #2F531D
uniform vec3 foliage_mid_color    : source_color = vec3(0.294, 0.471, 0.137); // #4B7823
uniform vec3 foliage_lit_color    : source_color = vec3(0.529, 0.659, 0.145); // #87A825
uniform vec3 foliage_rim_color    : source_color = vec3(0.800, 0.894, 0.306); // #CCE44E
uniform vec3 bark_lit_color       : source_color = vec3(0.478, 0.365, 0.275); // #7A5D46
uniform vec3 bark_shadow_color    : source_color = vec3(0.196, 0.173, 0.208); // #322C35

uniform float normal_sphere_blend : hint_range(0.0, 1.0) = 0.80;
uniform float normal_cluster_blend : hint_range(0.0, 1.0) = 0.48;
uniform float cluster_scale : hint_range(0.4, 3.0) = 1.15;
uniform float canopy_bottom_darken : hint_range(0.0, 0.6) = 0.28;
uniform float max_saturation : hint_range(0.3, 1.0) = 0.64;
uniform float texture_detail_weight : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.5) = 0.38;
uniform float instance_variation : hint_range(0.0, 1.0) = 1.0;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;

uniform mat4 tree_transform = mat4(1.0);
uniform vec3 canopy_center = vec3(0.0, 2.5, 0.0);
uniform float tree_height = 4.5;

varying float v_height_grad;
varying float v_canopy_ao;
varying float v_cluster_ao;
varying vec3 v_bent_normal_ws;
varying float v_foliage_mask;
varying float v_detail_mod;

vec3 sample_5stop(float t) {
	float x = clamp(t, 0.0, 1.0);
	vec3 c = mix(foliage_core_color, foliage_shadow_color, smoothstep(0.05, 0.28, x));
	c = mix(c, foliage_mid_color, smoothstep(0.28, 0.56, x));
	c = mix(c, foliage_lit_color, smoothstep(0.56, 0.82, x));
	c = mix(c, foliage_rim_color, smoothstep(0.82, 0.96, x));
	return c;
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

void vertex() {
	vec3 tree_pos = (tree_transform * vec4(VERTEX, 1.0)).xyz;
	v_height_grad = clamp(tree_pos.y / max(tree_height, 0.1), 0.0, 1.0);

	if (wind_strength > 0.001 && v_height_grad > 0.20) {
		float phase = TIME * 1.5 + tree_pos.x * 1.6 + tree_pos.z * 1.1;
		float sway = sin(phase) * 0.035 * wind_strength * smoothstep(0.20, 0.85, v_height_grad);
		VERTEX.x += sway;
		VERTEX.z += cos(phase * 0.8) * sway * 0.55;
	}

	vec3 to_center = tree_pos - canopy_center;
	vec3 canopy_dir = normalize(vec3(to_center.x, to_center.y * 0.90 + 0.08, to_center.z));
	float radial_dist = length(to_center / vec3(1.65, 1.85, 1.65));
	v_canopy_ao = clamp(mix(0.38, 1.0, smoothstep(0.12, 0.88, radial_dist)), 0.0, 1.0);

	vec3 scaled_p = (tree_pos - vec3(0.0, 0.8, 0.0)) / max(cluster_scale, 0.3);
	vec3 cell_id = floor(scaled_p);
	vec3 cell_jitter = (hash33(cell_id) - 0.5) * 0.32;
	vec3 cluster_center = (cell_id + vec3(0.5) + cell_jitter) * cluster_scale + vec3(0.0, 0.8, 0.0);
	vec3 to_cluster = tree_pos - cluster_center;
	vec3 cluster_dir = normalize(vec3(to_cluster.x, to_cluster.y * 1.15 + 0.10, to_cluster.z));
	float cluster_bottom = smoothstep(-0.45 * cluster_scale, 0.38 * cluster_scale, to_cluster.y);
	v_cluster_ao = mix(0.72, 1.06, cluster_bottom);

	vec3 combined_sphere_tree = normalize(mix(canopy_dir, cluster_dir, normal_cluster_blend));
	vec3 sphere_dir_local = normalize((inverse(tree_transform) * vec4(combined_sphere_tree, 0.0)).xyz);
	v_bent_normal_ws = normalize((MODEL_MATRIX * vec4(sphere_dir_local, 0.0)).xyz);
}

void fragment() {
	float mip_bias = (style == 1) ? 0.45 : 1.35;
	vec4 c = texture(base_map, UV, mip_bias);
	if (cutout) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}

	// Fix lower-canopy brown tint bug on combined meshes: classify foliage strictly by green dominance!
	float green_dominance = c.g - max(c.r * 0.86, c.b * 1.02);
	float foliage_mask = cutout ? 1.0 : (is_combined_mesh ? smoothstep(-0.02, 0.025, green_dominance) * smoothstep(0.06, 0.16, v_height_grad) : 0.0);
	v_foliage_mask = foliage_mask;

	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (foliage_mask > 0.01) {
		vec3 bent_normal_vs = normalize((VIEW_MATRIX * vec4(v_bent_normal_ws, 0.0)).xyz);
		float blend_amt = (style == 1) ? normal_sphere_blend : min(normal_sphere_blend + 0.14, 0.95);
		NORMAL = normalize(mix(NORMAL, bent_normal_vs, blend_amt * foliage_mask));
	}

	float tex_luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	float norm_detail = clamp(tex_luma / max(mix(0.055, 0.075, foliage_mask), 0.01), 0.72, 1.25);
	float detail_w = (style == 1) ? texture_detail_weight : texture_detail_weight * 0.35;
	v_detail_mod = mix(1.0, norm_detail, detail_w);

	float height_t = smoothstep(0.15, 0.88, v_height_grad);
	float base_t = clamp(height_t * 0.48 + v_canopy_ao * 0.36 + (v_cluster_ao - 0.72) * 0.5 - 0.08, 0.08, 0.65);
	vec3 leaf_base = sample_5stop(base_t) * v_detail_mod;
	vec3 bark_base = mix(bark_shadow_color, bark_lit_color, 0.55) * v_detail_mod;
	ALBEDO = mix(bark_base, leaf_base, foliage_mask);

	AO = mix(0.28, 1.0, mix(smoothstep(0.0, 0.35, v_height_grad), v_canopy_ao * v_cluster_ao, foliage_mask));
	AO_LIGHT_AFFECT = 0.75;
	ROUGHNESS = (style == 1) ? 0.76 : 0.90;
	SPECULAR = (style == 1) ? 0.18 : 0.06;

	if (has_normal) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		float leaf_nrm_depth = (style == 1) ? 0.14 : 0.02;
		float bark_nrm_depth = (style == 1) ? 0.58 : 0.28;
		NORMAL_MAP_DEPTH = mix(bark_nrm_depth, leaf_nrm_depth, foliage_mask);
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float ndl_clamped = max(ndl, 0.0);
	float is_leaf = clamp(v_foliage_mask, 0.0, 1.0);

	float half_l = ndl * 0.5 + 0.5;
	float shadow_atten = mix(0.25, 1.0, ATTENUATION);
	float height_t = smoothstep(0.15, 0.88, v_height_grad);
	float score = half_l * shadow_atten * 0.54 + height_t * 0.26 + v_canopy_ao * 0.22 - 0.04;

	vec3 leaf_target;
	if (style == 1) {
		leaf_target = sample_5stop(clamp(score, 0.04, 0.90)) * v_detail_mod;
		float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.6) * smoothstep(-0.1, 0.6, dot(-LIGHT, NORMAL)) * ATTENUATION;
		leaf_target = mix(leaf_target, foliage_rim_color, clamp(rim * rim_strength * 0.35, 0.0, 0.28));
	} else {
		leaf_target = foliage_core_color;
		leaf_target = mix(leaf_target, foliage_shadow_color, smoothstep(0.24, 0.26, score));
		leaf_target = mix(leaf_target, foliage_mid_color,    smoothstep(0.46, 0.48, score));
		leaf_target = mix(leaf_target, foliage_lit_color,    smoothstep(0.68, 0.70, score));
		leaf_target = mix(leaf_target, foliage_rim_color,    smoothstep(0.84, 0.86, score));
		float ndv = abs(dot(NORMAL, VIEW));
		float contour_ink = smoothstep(0.32, 0.14, ndv) * smoothstep(0.85, 0.32, score);
		leaf_target = mix(leaf_target, foliage_core_color * 0.65, contour_ink * 0.55);
	}

	float trunk_ao = mix(0.55, 1.0, smoothstep(0.0, 0.25, v_height_grad)) * (1.0 - 0.38 * smoothstep(0.35, 0.55, v_height_grad));
	vec3 bark_target = mix(bark_shadow_color, bark_lit_color, smoothstep(0.30, 0.65, half_l * shadow_atten)) * trunk_ao * v_detail_mod;
	vec3 target_col = mix(bark_target, leaf_target, is_leaf);

	vec3 color_ratio = target_col / max(ALBEDO, vec3(0.012));
	vec3 light_norm = clamp(LIGHT_COLOR / PI, vec3(0.0), vec3(1.08));
	DIFFUSE_LIGHT += color_ratio * 0.78 * light_norm;
}
