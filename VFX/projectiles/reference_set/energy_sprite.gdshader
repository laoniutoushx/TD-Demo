shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.2,0.8,1.0,1.0);
uniform float opacity = 0.5;
uniform float energy = 1.0;
uniform int shape = 0;
void vertex() {
 MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),MODEL_MATRIX[3]);
}
void fragment() {
 vec2 p = UV*2.0-1.0;
 float r = length(p);
 float a = pow(max(1.0-r,0.0),3.0);
 if (shape == 1) {
  float rays = pow(max(1.0-abs(p.x),0.0),25.0)+pow(max(1.0-abs(p.y),0.0),25.0);
  float diagonals = pow(max(1.0-abs(p.x-p.y)*0.707,0.0),38.0)+pow(max(1.0-abs(p.x+p.y)*0.707,0.0),38.0);
  a = (rays+diagonals*0.35)*pow(max(1.0-r,0.0),1.3)+a;
 }
 ALBEDO = tint.rgb*energy;
 EMISSION = tint.rgb*energy;
 ALPHA = clamp(a*opacity*tint.a,0.0,1.0);
}
