shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D flow_noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color = vec4(0.65,0.85,0.92,1.0);
uniform vec4 highlight : source_color = vec4(0.92,0.98,1.0,1.0);
uniform float clock = 0.0;
uniform float formation = 1.0;
uniform float height = 5.8;
uniform float emission_strength = 0.25;
uniform float opacity = 0.8;
uniform float dark_core = 0.0;
uniform float seed = 0.0;
uniform int kind = 0;
uniform int style = 0;
varying vec3 local_pos;
varying vec3 local_normal;
void vertex(){
 float h=clamp(VERTEX.y/height,0.0,1.2);
 float a=clock*0.6;
 VERTEX.xz+=vec2(sin(h*4.8+a),cos(h*3.8-a*0.7))*0.42*h;
 VERTEX.y+=sin(UV.x*25.13274+h*4.0+clock*0.6)*0.13*pow(h,4.0);
 float ripple=sin(h*18.0+UV.x*12.0-clock*2.0)*0.035;
 VERTEX.xz*=1.0+ripple;
 local_pos=VERTEX;
 local_normal=NORMAL;
}
void fragment(){
 float h=clamp(local_pos.y/height,0.0,1.2);
 vec2 flow=vec2(UV.x*1.7-clock*0.085+seed,UV.y*1.1-clock*0.11);
 float n=texture(flow_noise,flow).r;
 float f=texture(flow_noise,flow*3.1+vec2(clock*0.045,seed)).r;
 float fiber=texture(flow_noise,vec2(UV.x*1.7-UV.y*3.4-clock*0.2,UV.y*0.8+n*0.25)).r;
 float mask=1.0;
 float bright=0.0;
 float shade=0.55+0.45*abs(dot(normalize(local_normal),normalize(vec3(0.5,0.8,0.2))));
 if(kind==0){
  float phase=UV.x*6.283185-UV.y*15.0-clock*2.5+(n-0.5)*3.2;
  float band=smoothstep(-0.35,0.8,sin(phase));
  mask=mix(0.32,1.0,band)*(0.55+n*0.45);
  mask*=smoothstep(0.22,0.43,n*0.6+f*0.4);
  mask*=1.0-smoothstep(0.81+n*0.13,1.0,h);
  mask*=mix(1.0,smoothstep(0.32,0.59,n+f*0.12),smoothstep(0.65,1.0,h));
  bright=pow(band,5.0)*smoothstep(0.48,0.72,fiber);
  if(dark_core>0.5) mask=max(mask,0.72)*(1.0-smoothstep(0.85,1.0,h));
 }else if(kind==1 || kind==3){
  float width=abs(UV.y*2.0-1.0);
  float ragged=0.18+n*1.20;
  mask=1.0-smoothstep(ragged-0.14,ragged,width);
  mask*=smoothstep(0.37,0.63,n*0.65+f*0.35);
  mask*=smoothstep(0.0,0.04,UV.x)*(1.0-smoothstep(0.94,1.0,UV.x));
  bright=smoothstep(0.38,0.78,width)*mask+smoothstep(0.58,0.8,fiber)*0.28;
 }else{
  float radial=abs(UV.y*2.0-1.0);
  float ground_noise=texture(flow_noise,vec2(UV.x*1.6-clock*0.12,UV.y*0.8+seed)).r;
  mask=(1.0-smoothstep(0.25,0.95,radial))*smoothstep(0.40,0.65,ground_noise);
  mask*=smoothstep(0.0,0.05,UV.x)*(1.0-smoothstep(0.93,1.0,UV.x));
  bright=smoothstep(0.55,0.8,ground_noise)*0.35;
 }
 vec3 pigment=mix(tint.rgb,highlight.rgb,bright*0.75);
 pigment*=mix(shade,0.055,dark_core*(1.0-bright*0.6));
 vec3 emission=highlight.rgb*bright*emission_strength;
 if(style==8){
  vec2 fire_uv=vec2(UV.x*2.0-UV.y*2.8-clock*0.23,UV.y*1.8-clock*0.31+seed);
  float flame=texture(flow_noise,fire_uv+vec2(n*0.22,f*0.13)).r;
  float flame_detail=texture(flow_noise,fire_uv*2.7+vec2(clock*0.1,0.0)).r;
  float heat=clamp((flame-0.28)*1.8+flame_detail*0.22+(1.0-h)*0.18,0.0,1.0);
  vec3 fire=mix(vec3(0.5,0.008,0.001),vec3(1.0,0.19,0.004),smoothstep(0.15,0.5,heat));
  fire=mix(fire,vec3(1.0,0.77,0.12),smoothstep(0.45,0.8,heat));
  pigment=fire*0.3;
  emission=fire*emission_strength*(0.12+heat*heat*2.0);
  mask*=smoothstep(0.25,0.45,flame+flame_detail*0.12);
  if(kind==2) emission*=0.22;
 }
 if(style==10){
  mask=step(0.38,mask);
  pigment=mix(vec3(0.28,0.34,0.40),vec3(0.90,0.94,0.98),step(0.46,fiber));
  emission=vec3(0.0);
 }
 float depth=texture(depth_texture,SCREEN_UV).r;
 vec4 scene=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);
 float surface_depth=-VERTEX.z;
 float scene_depth=-scene.z/scene.w;
 float contact=clamp((scene_depth-surface_depth)/0.18,0.0,1.0);
 ALBEDO=pigment+emission;
 EMISSION=emission;
 ALPHA=clamp(mask*opacity*formation*contact,0.0,0.97);
}
