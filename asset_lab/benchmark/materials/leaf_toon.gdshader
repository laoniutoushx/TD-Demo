shader_type spatial;
render_mode cull_disabled;
#include "res://asset_lab/benchmark/materials/leaf_common.gdshaderinc"
void light() {
 float ndl=max(dot(NORMAL,LIGHT),0.0);
 float score=ndl*mix(0.28,1.0,ATTENUATION)+v_tier*0.18;
 float band=mix(0.12,0.52,smoothstep(0.18,0.22,score));
 band=mix(band,0.94,smoothstep(0.52,0.56,score));
 band=mix(band,1.22,smoothstep(0.80,0.84,score));
 vec3 tint=mix(vec3(0.46,0.76,0.96),vec3(1.08,1.12,0.84),smoothstep(0.18,0.64,score));
 float ndv=abs(dot(NORMAL,VIEW));
 float contour=mix(0.48,1.0,smoothstep(0.14,0.32,ndv));
 DIFFUSE_LIGHT+=tint*(band*contour)*ATTENUATION*LIGHT_COLOR/PI;
}
