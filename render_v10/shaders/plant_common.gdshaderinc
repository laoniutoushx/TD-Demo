uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_map : hint_default_white, filter_linear_mipmap_anisotropic;
uniform bool has_base_map = true;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform bool has_ao = false;
uniform bool use_vertex_color = false;
uniform bool use_alpha_scissor = false;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec3 species_tint : source_color = vec3(0.88, 0.94, 0.84);
uniform vec3 clean_tint : source_color = vec3(0.32, 0.58, 0.24);
uniform float normal_strength : hint_range(0.0, 1.0) = 0.22;
uniform float normal_blend : hint_range(0.0, 1.0) = 0.62;
uniform float roughness : hint_range(0.0, 1.0) = 0.76;
uniform float variation : hint_range(0.0, 0.5) = 0.34;
uniform float texture_weight : hint_range(0.0, 1.0) = 0.54;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.52;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
uniform int style_mode = 1;
instance uniform vec4 plant_palette = vec4(1.0);
varying float v_tier;
varying vec3 v_plant_tint;

void vertex() {
	float world_h = max(VERTEX.y * length(MODEL_MATRIX[1].xyz), 0.0);
	float h = clamp(world_h / 0.92, 0.0, 1.0);
	float radial = clamp(length(VERTEX.xz) * length(MODEL_MATRIX[0].xyz) / 0.75, 0.0, 1.0);
	v_tier = clamp(mix(h * 0.72 + radial * 0.28, COLOR.g, use_vertex_color ? 0.30 : 0.0), 0.0, 1.0);

	// Clump normal bending so understory shrubs & ferns share the same volumetric dome shading as benchmark trees
	vec3 clump_n = normalize(vec3(VERTEX.x, max(VERTEX.y, 0.18) * 1.45, VERTEX.z));
	NORMAL = normalize(mix(NORMAL, clump_n, normal_blend));

	float root_lock = smoothstep(0.02, 0.38, world_h);
	float phase = TIME * 1.35 + dot(MODEL_MATRIX[3].xz, vec2(0.71, 0.37)) + VERTEX.x * 1.2 + VERTEX.z * 0.85;
	float sway = sin(phase) * wind_strength * root_lock * 0.024;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.82) * sway * 0.5;
	v_plant_tint = INSTANCE_CUSTOM.a > 0.5 ? INSTANCE_CUSTOM.rgb : plant_palette.rgb;
}

void fragment() {
	vec4 tex = has_base_map ? texture(base_map, UV) : vec4(1.0);
	if (use_alpha_scissor) {
		if (tex.a < 0.001) {
			discard;
		}
		ALPHA = tex.a;
		ALPHA_SCISSOR_THRESHOLD = 0.45;
	}
	vec3 base_rgb = tex.rgb * source_tint.rgb * species_tint;
	if (use_vertex_color) {
		base_rgb = COLOR.rgb * (has_base_map ? mix(vec3(1.0), tex.rgb * 1.10, 0.65) : vec3(1.0));
	}
	// Normalize overly dark scan albedos in stylized/toon modes so understory plants match the 3-tier value hierarchy
	float luma = max(dot(base_rgb, vec3(0.299, 0.587, 0.114)), 0.04);
	vec3 lifted_scan = base_rgb * mix(1.0, clamp(0.28 / luma, 0.85, 1.65), 1.0 - texture_weight);
	vec3 raw_albedo = mix(clean_tint * v_plant_tint, lifted_scan * v_plant_tint, texture_weight);

	float t = clamp(v_tier, 0.0, 1.0);
	vec3 cool_shift = style_mode == 0 ? vec3(0.74, 0.80, 0.74) : vec3(0.42, 0.66, 0.58);
	vec3 mid_shift  = style_mode == 0 ? vec3(0.96, 0.98, 0.92) : vec3(0.84, 1.04, 0.72);
	vec3 warm_shift = style_mode == 0 ? vec3(1.10, 1.12, 0.92) : vec3(1.28, 1.36, 0.74);
	vec3 tier_tint = t < 0.5 ? mix(cool_shift, mid_shift, smoothstep(0.08, 0.50, t)) : mix(mid_shift, warm_shift, smoothstep(0.50, 0.92, t));
	ALBEDO = raw_albedo * mix(vec3(1.0), tier_tint, clamp(variation * 2.5, 0.0, 1.0));

	float src_ao = clamp(0.42 + t * 0.58, 0.25, 1.0);
	if (has_ao) {
		src_ao = min(src_ao, mix(0.45, 1.0, texture(ao_map, UV).r));
	} else if (has_orm) {
		src_ao = min(src_ao, mix(0.45, 1.0, texture(orm_map, UV).r));
	}
	// Single indirect-light AO term; never bake into ALBEDO or direct light.
	AO = mix(1.0, src_ao, ao_strength);
	AO_LIGHT_AFFECT = 0.0;
	METALLIC = 0.0;
	float orm_rough = has_orm ? texture(orm_map, UV).g : 1.0;
	ROUGHNESS = clamp(roughness * mix(0.85, 1.05, orm_rough), 0.45, 0.96);
	SPECULAR = style_mode == 2 ? 0.04 : (style_mode == 0 ? 0.34 : 0.20);
	BACKLIGHT = ALBEDO * (style_mode == 0 ? 0.28 : 0.18);
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = FRONT_FACING ? normal_strength : normal_strength * 0.25;
	}
}
