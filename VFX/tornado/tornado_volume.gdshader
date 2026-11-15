shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler3D density_noise : repeat_enable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float effect_time = 0.0;
uniform float height = 9.5;
uniform float radius = 2.65;
uniform float rotation_speed = 1.0;
uniform float flow_speed = 1.0;
uniform float optical_density = 3.8;
uniform vec4 smoke_color : source_color = vec4(0.42,0.44,0.46,1.0);
uniform vec4 dust_color : source_color = vec4(0.34,0.27,0.18,1.0);
uniform float formation = 1.0;
uniform int march_steps = 48;
uniform vec3 light_direction = vec3(0.5,0.8,0.3);
uniform vec3 sun_color = vec3(1.0);
uniform float sun_strength = 0.8;
uniform float ambient_strength = 0.3;
varying vec3 local_position;
varying mat4 world_to_local;
void vertex(){ local_position=VERTEX; world_to_local=inverse(MODEL_MATRIX); }
float field(vec3 p){
 float h=p.y/height;
 if(h<0.0 || h>1.0) return 0.0;
 vec2 axis=vec2(sin(h*3.7+effect_time*0.32),cos(h*4.6-effect_time*0.24))*radius*0.15*h;
 vec2 q=p.xz-axis;
 float r=length(q);
 float funnel=radius*(0.15+0.85*pow(h,1.25));
 float a=effect_time*rotation_speed*(1.25-0.65*h)+h*3.0;
 mat2 rot=mat2(vec2(cos(a),sin(a)),vec2(-sin(a),cos(a)));
 vec3 flow=vec3(rot*q,p.y*0.62-effect_time*flow_speed*height*0.17)/radius;
 float n=texture(density_noise,flow*0.31).r;
 float fine=texture(density_noise,flow*1.65+vec3(0.21,0.4,effect_time*flow_speed*0.025)).r;
 float edge=1.0-smoothstep(funnel*0.45,funnel*(0.72+n*0.65),r);
 float body=edge*smoothstep(0.23,0.68,n*0.68+fine*0.32);
 float skirt=(1.0-smoothstep(radius*0.35,radius*1.2,r))*exp(-h*height/(radius*0.19))*(n*0.8+fine*0.2)*0.65;
 return (body+skirt)*smoothstep(0.0,0.025,h)*(1.0-smoothstep(0.64,1.0,h))*formation;
}
void fragment(){
 vec3 camera_local=(world_to_local*vec4(CAMERA_POSITION_WORLD,1.0)).xyz;
 vec3 direction=normalize(local_position-camera_local);
 // Orthographic preview cameras need parallel rays.
 if(PROJECTION_MATRIX[3][3]>0.5){
  direction=normalize((world_to_local*vec4(-INV_VIEW_MATRIX[2].xyz,0.0)).xyz);
  camera_local=local_position-direction*height*4.0;
 }
 vec3 bounds=vec3(radius*1.4,height*0.5,radius*1.4);
 vec3 origin=camera_local-vec3(0.0,height*0.5,0.0);
 vec3 inv_ray=1.0/(direction+vec3(0.000001));
 vec3 t0=(-bounds-origin)*inv_ray;
 vec3 t1=(bounds-origin)*inv_ray;
 vec3 lo=min(t0,t1),hi=max(t0,t1);
 float start=max(max(lo.x,lo.y),max(lo.z,0.0));
 float finish=min(min(hi.x,hi.y),hi.z);
 float depth=texture(depth_texture,SCREEN_UV).r;
 vec4 scene_view=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);
 scene_view/=scene_view.w;
 vec3 scene_local=(world_to_local*INV_VIEW_MATRIX*scene_view).xyz;
 finish=min(finish,dot(scene_local-camera_local,direction));
 float step_size=max(0.0,finish-start)/float(march_steps);
 float jitter=fract(sin(dot(FRAGCOORD.xy,vec2(12.9898,78.233)))*43758.5453);
 vec3 ray_light=normalize((world_to_local*vec4(light_direction,0.0)).xyz);
 vec3 color=vec3(0.0);
 float transmittance=1.0;
 for(int i=0;i<72;i++){
  if(i>=march_steps || transmittance<0.015) break;
  vec3 p=camera_local+direction*(start+(float(i)+jitter)*step_size);
  float d=field(p);
  if(d>0.002){
   float shadow=field(p+ray_light*radius*0.22)*0.6+field(p+ray_light*radius*0.6)*0.4;
   vec3 lighting=vec3(ambient_strength)+sun_color*sun_strength*exp(-shadow*optical_density*1.8);
   vec3 pigment=mix(dust_color.rgb,smoke_color.rgb,smoothstep(0.0,0.45,p.y/height));
   float alpha=1.0-exp(-d*step_size*optical_density);
   color+=transmittance*alpha*pigment*lighting;
   transmittance*=1.0-alpha;
  }
 }
 ALBEDO=color/max(1.0-transmittance,0.0001);
 ALPHA=1.0-transmittance;
}
