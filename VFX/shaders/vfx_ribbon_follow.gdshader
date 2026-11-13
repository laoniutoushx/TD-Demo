shader_type particles;
render_mode disable_force, disable_velocity;
void start() {
 COLOR = vec4(1.0);
 VELOCITY = vec3(0.0);
 TRANSFORM = EMISSION_TRANSFORM;
}
void process() {
 TRANSFORM = mat4(1.0);
 TRANSFORM[0][0] = length(EMISSION_TRANSFORM[0].xyz);
 TRANSFORM[1][1] = length(EMISSION_TRANSFORM[1].xyz);
 TRANSFORM[2][2] = length(EMISSION_TRANSFORM[2].xyz);
 TRANSFORM[3] = EMISSION_TRANSFORM[3];
}
