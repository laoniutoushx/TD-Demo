uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.22;
uniform float roughness : hint_range(0.0, 1.0) = 0.78;
uniform float variation : hint_range(0.0, 0.5) = 0.22;
uniform float wind_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 clean_tint : source_color = vec3(0.32, 0.54, 0.15);
uniform float texture_weight : hint_range(0.0, 1.0) = 1.0;
uniform int style_mode = 1; // 0 = Realistic PBR, 1 = Hand-Painted PBR, 2 = Top-Down Gameplay

// Concept Sheet 5-Stop Broadleaf Palette (sRGB source_color -> Linear)
uniform vec3 col_core_shadow : source_color = vec3(0.094, 0.173, 0.078); // #182C14 Deep Core
uniform vec3 col_dark_forest : source_color = vec3(0.184, 0.325, 0.114); // #2F531D Canopy Shadow
uniform vec3 col_mid_green   : source_color = vec3(0.294, 0.471, 0.137); // #4B7823 Mid Foliage
uniform vec3 col_warm_sunlit : source_color = vec3(0.529, 0.659, 0.145); // #87A825 Warm Sunlit
uniform vec3 col_bright_tip  : source_color = vec3(0.800, 0.894, 0.306); // #CCE44E Crown Tip Accent

varying float v_spatial_ao;
varying float v_palette_grad;
varying float v_tip_weight;
varying float v_detail_mod;

vec3 sample_5stop_palette(float t) {
	float x = clamp(t, 0.0, 1.0);
	vec3 c = mix(col_core_shadow, col_dark_forest, smoothstep(0.04, 0.28, x));
	c = mix(c, col_mid_green, smoothstep(0.28, 0.54, x));
	c = mix(c, col_warm_sunlit, smoothstep(0.54, 0.80, x));
	c = mix(c, col_bright_tip, smoothstep(0.80, 0.96, x));
	return c;
}

void vertex() {
	v_spatial_ao = clamp(COLOR.r, 0.12, 1.0);
	v_palette_grad = clamp(COLOR.g, 0.0, 1.0);
	v_tip_weight = clamp(COLOR.b, 0.0, 1.0);

	float phase = TIME * 1.45 + VERTEX.x * 1.2 + VERTEX.z * 0.85;
	float sway = sin(phase) * wind_strength * v_tip_weight * 0.045;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.8) * sway * 0.55;
}

void fragment() {
	vec3 tex_col = texture(base_map, UV).rgb;
	float tex_luma = dot(tex_col, vec3(0.2126, 0.7152, 0.0722));
	v_detail_mod = clamp(tex_luma / 0.14, 0.72, 1.28);

	if (style_mode == 0) {
		// Style 0: Realistic PBR — rich natural leaf texture + deep cavity occlusion
		vec3 nat_col = mix(clean_tint, tex_col, texture_weight);
		float var_factor = mix(0.68, 1.32, v_palette_grad);
		float ao_darken = mix(0.32, 1.08, v_spatial_ao);
		ALBEDO = nat_col * var_factor * ao_darken;
		AO = mix(0.18, 1.0, v_spatial_ao);
		AO_LIGHT_AFFECT = 0.85;
		SPECULAR = 0.35;
		BACKLIGHT = ALBEDO * 0.24 * v_tip_weight;
	} else if (style_mode == 1) {
		// Style 1: Hand-Painted PBR — Concept Sheet 5-stop painterly palette + soft brush detail
		float base_t = clamp(v_palette_grad * 0.55 + v_spatial_ao * 0.35 - 0.08, 0.08, 0.65);
		vec3 painted_base = sample_5stop_palette(base_t) * mix(1.0, v_detail_mod, 0.36 * texture_weight);
		ALBEDO = painted_base;
		AO = mix(0.25, 1.0, v_spatial_ao);
		AO_LIGHT_AFFECT = 0.75;
		SPECULAR = 0.18;
		BACKLIGHT = ALBEDO * 0.18;
	} else {
		// Style 2: Top-Down Gameplay — clean macro canopy layers
		float layer_t = clamp(v_palette_grad * 0.55 + v_spatial_ao * 0.38 - 0.06, 0.10, 0.68);
		vec3 game_base = sample_5stop_palette(layer_t) * mix(1.0, v_detail_mod, 0.12 * texture_weight);
		ALBEDO = game_base;
		AO = mix(0.28, 1.0, v_spatial_ao);
		AO_LIGHT_AFFECT = 0.72;
		SPECULAR = 0.06;
		BACKLIGHT = ALBEDO * 0.15;
	}

	// Undo Godot's automatic backface normal flip so baked dome normals stay outward
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = FRONT_FACING ? normal_strength : normal_strength * 0.30;
	METALLIC = 0.0;
	ROUGHNESS = roughness;
}
