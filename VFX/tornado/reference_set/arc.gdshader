shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never;
uniform float clock=0.0;
uniform float formation=1.0;
uniform vec4 color : source_color = vec4(0.38,0.62,1.0,1.0);
void fragment(){
 float flash=step(0.42,sin(floor(clock*11.0)*2.73+UV.x*1.4));
 float edge=1.0-smoothstep(0.15,0.98,abs(UV.y*2.0-1.0));
 ALBEDO=mix(color.rgb,vec3(1.0),0.5)*4.0;
 EMISSION=mix(color.rgb,vec3(1.0),0.5)*4.0;
 ALPHA=edge*flash*formation;
}
