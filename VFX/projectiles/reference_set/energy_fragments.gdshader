shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 1.0;
void fragment() {
 ALBEDO = COLOR.rgb*tint.rgb*energy;
 EMISSION = COLOR.rgb*tint.rgb*energy;
 ALPHA = COLOR.a*tint.a;
}
