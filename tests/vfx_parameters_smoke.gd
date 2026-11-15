extends SceneTree
var failures: int=0
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
 if not value:
  failures+=1
  push_error("VFX_PARAMETERS_FAILED: "+message)
func frames(count: int=3) -> void:
 for i in count: await process_frame
func run() -> void:
 root.size=Vector2i(1600,900)
 var catalog=load("res://VFX/lab/vfx_parameter_catalog.gd")
 var base=load("res://System/vfx_system/domain/VFXInstance.gd").new()
 var duration_safe: bool=false
 for binding in catalog.properties(base):
  if binding.property=="duration": duration_safe=binding.key=="property:duration"
 check(duration_safe,"Effect duration cannot collide with transport duration")
 base.free()
 var lab=load("res://VFX/lab/VFXLab.tscn").instantiate()
 root.add_child(lab)
 await frames()
 lab.select_effect(lab._path_index("res://VFX/tornado/reference_set/vfx_tornado_wind_running.tscn"))
 check(lab.effect.style==0,"White wind retained")
 check(lab._native_rows.has("flow_speed") and lab._native_rows.has("wind_opacity"),"Tornado schema discovered")
 lab._fields.rotation_speed[1].value=2.4
 lab._fields.flow_speed[1].value=0.35
 lab._fields.wind_opacity[1].value=0.7
 lab.set_paused(true)
 await frames()
 check(is_equal_approx(lab.effect.rotation_speed,2.4),"Live rotation")
 check(is_equal_approx(lab.effect.mats[0].get_shader_parameter("clock"),lab.effect.age*0.35),"Independent shader flow while paused")
 var identity: int=lab.effect.get_instance_id()
 lab._fields.flow_speed[1].value=1.7
 check(lab.effect.get_instance_id()==identity,"Live edit avoids rebuild")
 lab.record_a()
 lab._fields.flow_speed[1].value=0.2
 lab.swap_ab()
 check(is_equal_approx(lab.effect.flow_speed,1.7),"A/B restores properties")
 DirAccess.make_dir_recursive_absolute("res://.godot/vfx_parameters")
 lab.save_preset("res://.godot/vfx_parameters/white_wind.tres")
 lab._fields.flow_speed[1].value=0.4
 check(lab.load_preset("res://.godot/vfx_parameters/white_wind.tres"),"Preset loads")
 check(is_equal_approx(lab.effect.flow_speed,1.7),"Preset restores flow")
 lab.set_paused(false)
 lab.replay()
 check(is_equal_approx(lab.effect.wind_opacity,0.7),"Replay restores opacity")
 lab._set_native("style",11)
 await frames(4)
 check(lab.effect.style==11,"Enum rebuild supports all 12 styles")
 lab.select_effect(lab._path_index("res://VFX/tornado/vfx_tornado_running.tscn"))
 check(lab._native_rows.has("funnel_height"),"Different effect exposes its own parameters")
 lab._fields.funnel_height[1].value=7.0
 await frames(4)
 check(is_equal_approx(lab.effect.get_node("VolumetricFunnel").get_aabb().size.y,7.0),"Geometry parameters rebuild before ready")
 lab.select_effect(lab._path_index("res://VFX/shockwave/vfx_shockwave_running.tscn"))
 var shader_key: String=""
 var color_key: String=""
 for key in lab._native_bindings:
  var binding: Dictionary=lab._native_bindings[key]
  if binding.shader and binding.property=="distortionView": shader_key=key
  if binding.shader and int(binding.type)==TYPE_COLOR: color_key=key
 check(not shader_key.is_empty(),"Legacy shader uniforms discovered")
 if not shader_key.is_empty():
  lab._fields[shader_key][1].value=0.07
  check(is_equal_approx(lab._native_bindings[shader_key].target.get_shader_parameter("distortionView"),0.07),"Raw shader editing")
  lab.replay()
  check(is_equal_approx(lab._native_bindings[shader_key].target.get_shader_parameter("distortionView"),0.07),"Shader value survives replay")
 if not color_key.is_empty():
  lab._set_native(color_key,Color(0.2,0.4,0.6,1))
  lab.preset.intensity=0.5
  lab.apply_parameters()
  var binding: Dictionary=lab._native_bindings[color_key]
  var color: Color=binding.target.get_shader_parameter(binding.property)
  check(is_equal_approx(color.r,0.1) and is_equal_approx(color.g,0.2),"Native colors compose with global tint")
 var authored=load("res://VFX/shockwave/vfx_shockwave_running.tscn").instantiate()
 for binding in catalog.discover(authored):
  if binding.shader and binding.property=="distortionView":
   check(is_equal_approx(binding.target.get_shader_parameter("distortionView"),0.03),"Authored shader resources remain unchanged")
 authored.free()
 lab.select_effect(lab._path_index("res://VFX/blood/vfx_blood_burning.tscn"))
 var particle_key: String=""
 for key in lab._native_bindings:
  if str(key).begins_with("particle:") and str(key).ends_with(":amount"): particle_key=key
 check(not particle_key.is_empty(),"Particle-only scene exposes parameters")
 if not particle_key.is_empty():
  lab._fields[particle_key][1].value=48
  lab.replay()
  check(lab._native_bindings[particle_key].target.amount==48,"Particle count survives replay")
 lab.select_effect(lab._path_index("res://VFX/tornado/reference_set/vfx_tornado_wind_running.tscn"))
 check(lab.effect.style==0 and lab.effect.flow_speed==1.0,"Switching never overwrites preserved white wind")
 if DisplayServer.get_name()!="headless":
  await create_timer(1.0).timeout
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/vfx_parameters/panel.png")
 lab.stop()
 lab.queue_free()
 await frames()
 if failures==0: print("VFX_PARAMETERS_OK")
 quit(1 if failures else 0)
