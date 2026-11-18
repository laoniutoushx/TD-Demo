extends RefCounted
## Exported script properties and unmanaged shader uniforms form a per-effect schema.
const LABELS={"growth_duration":"成形时间","growth_start_scale":"初始尺寸比例","vortex_power":"卷动力度","wind_band_strength":"旋转风带强度","rotation_speed":"旋转速度","flow_speed":"气流 / 纹理流动速度","wind_opacity":"风带透明度","emission_scale":"能量亮度","debris_scale":"碎石尺度","smoke_opacity":"悬尘浓度","style":"效果样式","radius":"半径","density":"碎片数量","emission_energy":"发光能量","trail_length":"尾迹长度","dynamic_light":"动态灯光","pulse_period":"脉冲周期（秒）","funnel_height":"漏斗高度","funnel_radius":"漏斗半径","optical_density":"烟尘厚度","volume_steps":"体积采样步数","speed":"流动速度","core_color":"核心颜色","glow_color":"电晕颜色","branch_color":"分支颜色","bolt_width":"主干粗细","taper_power":"两端锥度","jitter_amplitude":"折线幅度","segment_density":"分段密度","fractal_roughness":"分形尖锐度","endpoint_lock":"端点锁定收敛","arc_lift":"电弧拱起高度","branch_count":"分支数量","branch_probability":"分支概率","branch_length_ratio":"分支长度比例","branch_width_ratio":"分支粗细比例","max_branch_depth":"分支级数","sub_arc_count":"伴生电弧数","sub_arc_spread":"伴生电弧扩散","multi_target_mode":"多目标叉状模式","fork_split_ratio":"公共电根分叉比","stray_fork_count":"辅助空叉数量","fork_width_scale":"次目标电叉粗细比","continuous_mode":"持续模式","propagation_speed":"窜动速度","flicker_fps":"闪烁帧率","uv_scroll_speed":"等离子流速","hold_duration":"主闪持续时间","fade_duration":"余辉消散时间","restrike_count":"余震闪烁次数","light_color":"点光颜色","light_energy":"点光强度","frequency":"波形频率","amplitude":"抖动幅度","world_tiling":"世界平铺密度","noise_speed":"闪烁速度","opacity":"不透明度"}
const LIVE=["rotation_speed","trail_length","density","pulse_period","optical_density","volume_steps","core_color","glow_color","branch_color","emission_energy","bolt_width","taper_power","jitter_amplitude","segment_density","fractal_roughness","endpoint_lock","arc_lift","branch_count","branch_probability","branch_length_ratio","branch_width_ratio","max_branch_depth","sub_arc_count","sub_arc_spread","multi_target_mode","fork_split_ratio","stray_fork_count","fork_width_scale","continuous_mode","propagation_speed","flicker_fps","uv_scroll_speed","hold_duration","fade_duration","restrike_count","dynamic_light","light_color","light_energy","frequency","amplitude","world_tiling","noise_speed","opacity"]
static func properties(effect: Node) -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 var script: Script=effect.get_script()
 if script==null: return result
 var overrides: Dictionary=effect.call("get_vfx_parameter_schema") if effect.has_method("get_vfx_parameter_schema") else {}
 for property in script.get_script_property_list():
  if (int(property.usage)&PROPERTY_USAGE_EDITOR)==0: continue
  if int(property.type) not in [TYPE_FLOAT,TYPE_INT,TYPE_BOOL,TYPE_COLOR,TYPE_VECTOR2,TYPE_VECTOR3]: continue
  var key: String=property.name
  if key in ["auto_recycle","camera_trauma","trauma_max_distance"]: continue
  var entry: Dictionary=property.duplicate()
  entry.merge({"key":("property:"+key if key in ["scale","duration","intensity"] else key),"label":LABELS.get(key,key.capitalize()),"target":effect,"property":key,"shader":false,"live":key in LIVE},true)
  entry.merge(overrides.get(key,{}),true)
  result.append(entry)
 return result
static func discover(effect: Node) -> Array[Dictionary]:
 var result:=properties(effect)
 # Controllers own their uniforms; edit their exported API instead of fighting _process.
 if effect.has_method("seek_preview"): return result
 var nodes: Array[Node]=[effect]
 nodes.append_array(effect.find_children("*","GeometryInstance3D",true,false))
 var visited: Dictionary={}
 for node in nodes:
  if not node is GeometryInstance3D: continue
  var candidates: Array=[]
  if node is GPUParticles3D:
   for setting in [["amount","粒子数量",1,2048,1],["lifetime","粒子寿命",0.05,30,0.05],["speed_scale","粒子模拟速度",0,8,0.05]]:
    result.append(_particle_entry(effect,node,node,"particle",setting))
   if node.process_material is ParticleProcessMaterial:
    for setting in [["initial_velocity_min","最小初速",0,100,0.1],["initial_velocity_max","最大初速",0,100,0.1],["scale_min","最小尺寸",0.01,20,0.05],["scale_max","最大尺寸",0.01,20,0.05],["gravity","重力方向与强度",-100,100,0.1]]:
     result.append(_particle_entry(effect,node,node.process_material,"process",setting))
   elif node.process_material is ShaderMaterial:
    candidates.append(["process",node.process_material])
  if node.material_override: candidates.append(["override",node.material_override])
  var mesh: Mesh=null
  if node is MeshInstance3D: mesh=node.mesh
  elif node is MultiMeshInstance3D and node.multimesh: mesh=node.multimesh.mesh
  if mesh:
   for i in mesh.get_surface_count(): candidates.append(["surface%d"%i,mesh.surface_get_material(i)])
  if node is GPUParticles3D:
   for i in node.draw_passes:
    var draw_mesh: Mesh=node.get_draw_pass_mesh(i)
    if draw_mesh:
     for j in draw_mesh.get_surface_count(): candidates.append(["pass%d_surface%d"%[i,j],draw_mesh.surface_get_material(j)])
  for candidate in candidates:
   var material=candidate[1]
   if not material is ShaderMaterial or material.shader==null or visited.has(material): continue
   visited[material]=true
   for uniform in material.shader.get_shader_uniform_list():
    var name: String=uniform.name
    if name in ["clock","effect_time","time","formation","light_direction","sun_strength","ambient_strength","sun_color"]: continue
    var value=material.get_shader_parameter(name)
    if typeof(value) not in [TYPE_FLOAT,TYPE_INT,TYPE_BOOL,TYPE_COLOR,TYPE_VECTOR2,TYPE_VECTOR3]: continue
    var entry: Dictionary=uniform.duplicate()
    entry.type=typeof(value)
    entry.merge({"key":"shader:%s:%s:%s"%[effect.get_path_to(node),candidate[0],name],"label":str(node.name)+" · "+str(LABELS.get(name,name.capitalize())),"target":material,"property":name,"shader":true,"live":true},true)
    result.append(entry)
 return result
static func value(entry: Dictionary) -> Variant:
 return entry.target.get_shader_parameter(entry.property) if entry.shader else entry.target.get(entry.property)
static func limits(entry: Dictionary,current: Variant) -> Vector3:
 var integer: bool=int(entry.type)==TYPE_INT
 var low: float=0.0 if float(current)>=0.0 else -maxf(10.0,absf(float(current))*4.0)
 var high: float=maxf(10.0,absf(float(current))*4.0)
 var step: float=1.0 if integer else 0.05
 if int(entry.get("hint",0))==PROPERTY_HINT_RANGE:
  var parts: PackedStringArray=str(entry.get("hint_string","")).split(",")
  if parts.size()>=2:
   low=float(parts[0]); high=float(parts[1])
  if parts.size()>=3 and parts[2].is_valid_float(): step=float(parts[2])
 return Vector3(low,high,step)
static func sanitize(entry: Dictionary,input: Variant) -> Variant:
 var kind: int=int(entry.type)
 if kind in [TYPE_FLOAT,TYPE_INT]:
  if typeof(input) not in [TYPE_FLOAT,TYPE_INT] or not is_finite(float(input)): return value(entry)
  if int(entry.get("hint",0))==PROPERTY_HINT_ENUM:
   var expected: int=0
   for item in str(entry.get("hint_string","")).split(","):
    var pair: PackedStringArray=item.split(":")
    if pair.size()>1: expected=int(pair[1])
    if int(input)==expected: return expected
    expected+=1
   return value(entry)
  var bounds:=limits(entry,value(entry))
  var number: float=clampf(float(input),bounds.x,bounds.y)
  return int(round(number)) if kind==TYPE_INT else number
 return input if typeof(input)==kind else value(entry)
static func assign(entry: Dictionary,input: Variant) -> void:
 if entry.shader: entry.target.set_shader_parameter(entry.property,input)
 else: entry.target.set(entry.property,input)

static func _particle_entry(effect: Node,node: Node,target: Object,prefix: String,setting: Array) -> Dictionary:
 var name: String=setting[0]
 var current: Variant=target.get(name)
 return {"key":"%s:%s:%s"%[prefix,effect.get_path_to(node),name],"label":str(node.name)+" · "+str(setting[1]),"target":target,"property":name,"shader":false,"live":true,"type":typeof(current),"hint":PROPERTY_HINT_RANGE,"hint_string":"%s,%s,%s"%[setting[2],setting[3],setting[4]]}
