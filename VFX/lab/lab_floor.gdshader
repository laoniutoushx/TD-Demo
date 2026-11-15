shader_type spatial;
render_mode cull_back;
uniform vec4 floor_color : source_color = vec4(0.10,0.12,0.15,1.0);
uniform bool show_grid = true;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float grid_line(vec2 p) {
 vec2 width = max(fwidth(p),vec2(0.0001));
 vec2 d = abs(fract(p-0.5)-0.5)/width;
 return 1.0-min(min(d.x,d.y),1.0);
}
void fragment() {
 float fade = 1.0-smoothstep(7.0,28.0,length(world_position.xz));
 float grid = show_grid ? (grid_line(world_position.xz)*0.20+grid_line(world_position.xz/5.0)*0.22)*fade : 0.0;
 ALBEDO = mix(floor_color.rgb,floor_color.rgb*1.7+vec3(0.025),clamp(grid,0.0,0.5));
 ROUGHNESS = 0.95;
 METALLIC = 0.0;
 SPECULAR = 0.15;
}
