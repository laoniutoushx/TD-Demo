shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://asset_lab/benchmark/materials/leaf_common.gdshaderinc"
// No light() override: Godot supplies roughness-dependent GGX lighting.
