shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.2,0.8,1.0,1.0);
uniform vec4 hot_tint : source_color = vec4(0.7,1.0,1.0,1.0);
uniform sampler2D noise_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D cells_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D mask_map : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float effect_time = 0.0;
uniform float opacity = 1.0;
uniform float energy = 1.0;
uniform float dissolve = 0.0;
uniform float flow = 0.7;
uniform int layer = 0;
uniform float trail_jitter = 0.035;

void vertex() {
 if (layer == 8) {
  float anchor = smoothstep(0.0,0.2,UV.x);
  VERTEX.x += (sin(effect_time*17.0+UV.x*24.0)+0.4*sin(effect_time*9.0+UV.x*11.0))*trail_jitter*anchor;
  VERTEX.y += cos(effect_time*13.0+UV.x*18.0)*trail_jitter*anchor;
 } else if (layer == 5 || layer == 7) {
  float lip = pow(UV.y,3.0);
  VERTEX += NORMAL*sin(UV.x*TAU*9.0+effect_time*8.0)*lip*0.018;
 }
}


void fragment() {
 vec2 uv = UV;
 float n = texture(noise_map, uv * vec2(3.0,2.0) + vec2(-effect_time*flow, effect_time*0.13)).r;
 float fine = texture(noise_map, uv*7.0 + vec2(effect_time*0.23,0.0)).r;
 float cracks = smoothstep(0.56,0.9,texture(cells_map,uv*vec2(3.0,2.0)+vec2(effect_time*0.03,0.0)).r);
 float alpha = 1.0;
 float heat = n;
 if (layer == 0) {
  // Ribbon UV.x is arc length, UV.y is width.
  float edge = pow(max(sin(uv.y*PI),0.0),0.7);
  float ends = smoothstep(0.0,0.035,uv.x)*(1.0-smoothstep(0.82,1.0,uv.x));
  float cut = smoothstep(0.19+dissolve*0.8,0.34+dissolve*0.8,n*0.7+fine*0.3);
  alpha = edge*ends*cut;
  heat = smoothstep(0.40,0.8,n)*0.75 + pow(max(1.0-abs(uv.y*2.0-1.0),0.0),8.0)*0.25;
 } else if (layer == 1) {
  float rim = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),2.0);
  float holes = smoothstep(0.34+dissolve*0.7,0.56+dissolve*0.7,n);
  alpha = holes*(0.13+rim*0.7+cracks*0.22);
  heat = clamp(rim*0.5+cracks*0.65,0.0,1.0);
 } else if (layer == 2) {
  float scan = pow(0.5+0.5*sin(uv.x*TAU*2.0-effect_time*5.0),8.0);
  alpha = (0.6+n*0.4)*(1.0-dissolve);
  heat = scan*0.65+fine*0.25;
 } else if (layer == 3) {
  float rim = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),2.5);
  alpha = 0.45+n*0.45;
  heat = rim*0.65+cracks*0.15;
 } else if (layer == 5) {
  // Crown UV: U wraps the axis, V goes from the round nose to the torn lip.
  float lip = smoothstep(0.48,0.95,uv.y);
  float torn = smoothstep(0.22+lip*0.24+dissolve*0.75,0.43+lip*0.24+dissolve*0.75,n*0.6+cracks*0.4);
  float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),1.5);
  float nose = 1.0-smoothstep(0.10,0.55,uv.y);
  alpha = torn*(0.23+rim*0.55+lip*0.27+nose*0.26)*(1.0-smoothstep(0.97,1.0,uv.y));
  heat = clamp(cracks*0.65+lip*0.65+rim*0.15+nose*0.60,0.0,1.0);
 } else if (layer == 6) {
  alpha = pow(max(sin(uv.y*PI),0.0),0.65)*(1.0-dissolve);
  heat = 0.1+fine*0.12;
 } else if (layer == 7) {
  float cut = smoothstep(0.20+dissolve*0.8,0.40+dissolve*0.8,n);
  float lip = smoothstep(0.3,0.9,uv.y);
  alpha = cut*(0.3+lip*0.55)*(1.0-smoothstep(0.92,1.0,uv.y));
  heat = 0.45+fine*0.3;
 } else if (layer == 8) {
  float edge = pow(max(sin(uv.y*PI),0.0),0.6);
  alpha = edge*(1.0-smoothstep(0.45,1.0,uv.x))*(0.5+n*0.5)*(1.0-dissolve);
  heat = smoothstep(0.40,0.85,abs(uv.y*2.0-1.0))*0.80+(1.0-uv.x)*0.12;
 } else {
  float edge = pow(max(sin(uv.y*PI),0.0),1.2);
  alpha = edge*texture(mask_map,vec2(uv.x,uv.y)).r*smoothstep(0.26+dissolve*0.7,0.5+dissolve*0.7,n);
  heat = n*0.65;
 }
 vec3 color = mix(tint.rgb,hot_tint.rgb,clamp(heat,0.0,1.0));
 ALBEDO = color*energy;
 EMISSION = color*energy;
 ALPHA = clamp(alpha*opacity*tint.a,0.0,1.0);
}
