uniform sampler2D base_map : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic;
uniform float normal_strength : hint_range(0.0,1.0) = 0.18;
uniform float roughness : hint_range(0.0,1.0) = 0.78;
uniform float variation : hint_range(0.0,0.5) = 0.14;
uniform float wind_strength : hint_range(0.0,1.0) = 0.0;
uniform vec3 clean_tint : source_color = vec3(0.28,0.52,0.20);
uniform float texture_weight : hint_range(0.0,1.0) = 1.0;
uniform float ao_strength : hint_range(0.0,1.0) = 0.45;
uniform int style_mode = 1;
varying float v_tier;
void vertex() {
 v_tier=COLOR.g;
 float phase=TIME*1.45+VERTEX.x*1.2+VERTEX.z*.85;
 float sway=sin(phase)*wind_strength*COLOR.b*.025;
 VERTEX.x+=sway;
 VERTEX.z+=cos(phase*.8)*sway*.5;
}
void fragment() {
 vec3 base=texture(base_map,UV).rgb;
 vec3 raw_albedo=mix(clean_tint,base,texture_weight);
 // COLOR.g is neutral per-leaf variation. Directional light supplies crown shading.
 float t=clamp(COLOR.g,0.0,1.0);
 vec3 cool_shift=style_mode==0?vec3(0.68,0.74,0.68):vec3(0.40,0.66,0.64);
 vec3 mid_shift=style_mode==0?vec3(0.92,0.95,0.88):vec3(0.78,0.96,0.74);
 vec3 warm_shift=style_mode==0?vec3(1.10,1.12,0.88):vec3(1.18,1.24,0.68);
 vec3 tier_tint=t<0.5?mix(cool_shift,mid_shift,smoothstep(0.12,0.50,t)):mix(mid_shift,warm_shift,smoothstep(0.50,0.88,t));
 ALBEDO=raw_albedo*mix(vec3(1.0),tier_tint,clamp(variation*2.5,0.0,1.0));
 // One indirect occlusion term from real visibility samples. Do not bake it into albedo.
 AO=mix(1.0,clamp(COLOR.r,0.0,1.0),ao_strength);
 AO_LIGHT_AFFECT=0.0;
 METALLIC=0.0;
 ROUGHNESS=roughness;
 SPECULAR=style_mode==2?0.04:(style_mode==0?0.38:0.20);
 BACKLIGHT=ALBEDO*(style_mode==0?0.14:0.10);
 if(!FRONT_FACING) NORMAL=-NORMAL;
 NORMAL_MAP=texture(normal_map,UV).rgb;
 NORMAL_MAP_DEPTH=FRONT_FACING?normal_strength:normal_strength*.2;
}
