extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 root.size = Vector2i(1280,800)
 root.msaa_2d = Viewport.MSAA_DISABLED
 var stage := Node3D.new()
 root.add_child(stage)
 var world := WorldEnvironment.new()
 var env := Environment.new()
 env.background_mode = Environment.BG_COLOR
 env.background_color = Color(0.22,0.27,0.32)
 env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.ambient_light_color = Color(0.7,0.75,0.82)
 env.ambient_light_energy = 0.7
 env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 world.environment = env
 stage.add_child(world)
 var sun := DirectionalLight3D.new()
 sun.rotation_degrees = Vector3(-45,-30,0)
 sun.light_energy = 1.8
 sun.shadow_enabled = true
 stage.add_child(sun)
 var floor_mesh := MeshInstance3D.new()
 var plane := PlaneMesh.new()
 plane.size = Vector2(1000,1000)
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color(0.3,0.32,0.28)
 mat.roughness = 1.0
 plane.material = mat
 floor_mesh.mesh = plane
 stage.add_child(floor_mesh)
 var camera := Camera3D.new()
 stage.add_child(camera)
 camera.position = Vector3(8.5,6,11)
 camera.look_at(Vector3(0,4.2,0))
 camera.current = true
 for i in 8:
  var marker := MeshInstance3D.new()
  var cylinder := CylinderMesh.new()
  cylinder.top_radius = 0.15
  cylinder.bottom_radius = 0.18
  cylinder.height = 1.8
  marker.mesh = cylinder
  marker.position = Vector3(float(i-4)*2.0,0.9,-3.0)
  stage.add_child(marker)
 var timings := {}
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 timings["empty"] = await measure_gpu()
 var paths := ["res://VFX/tornado/vfx_tornado_running.tscn","res://VFX/funnel_tornado/vfx_funnel_tornado_volume_running.tscn"]
 DirAccess.make_dir_recursive_absolute("res://.godot/tornado_review")
 for index in paths.size():
  var effect: Node3D = load(paths[index]).instantiate()
  stage.add_child(effect)
  effect.get_node("WindAudio").stream_paused = true
  if index == 0:
   assert(effect.get_node("Area3D").collision_mask == 2)
   assert(effect.get_node("Area3D/CollisionShape3D").shape.radius == 4.0)
  else:
   camera.position = Vector3(4,3,5)
   camera.look_at(Vector3(0,1.9,0))
  await create_timer(3.0).timeout
  effect.seek_preview(3.0)
  effect.set_process(false)
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://.godot/tornado_review/volume_%d.png" % index)
  if index == 0:
   timings["one_tornado"] = await measure_gpu()
   var extras: Array[Node3D] = []
   for side in [-1,1]:
    var extra: Node3D = load(paths[0]).instantiate()
    stage.add_child(extra)
    extra.position.x = side*3.5
    extra.get_node("WindAudio").stream_paused = true
    extra.seek_preview(3.0)
    extras.append(extra)
   await create_timer(0.5).timeout
   timings["three_tornadoes"] = await measure_gpu()
   for extra in extras: extra.queue_free()
   await process_frame
   if "--capture" in OS.get_cmdline_user_args():
    DirAccess.make_dir_recursive_absolute("res://.godot/tornado_review/sequence")
    for frame in 90:
     effect.seek_preview(1.0+float(frame)/30.0)
     await process_frame
     await RenderingServer.frame_post_draw
     root.get_texture().get_image().save_png("res://.godot/tornado_review/sequence/frame_%03d.png" % frame)
   camera.projection = Camera3D.PROJECTION_ORTHOGONAL
   camera.size = 13.0
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://.godot/tornado_review/ortho.png")
   camera.projection = Camera3D.PROJECTION_PERSPECTIVE
   camera.position = Vector3(0.05,3,0.05)
   camera.look_at(Vector3(3,4,2))
   await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://.godot/tornado_review/inside.png")
  assert(effect.global_position == Vector3.ZERO)
  effect.seek_preview(0.0)
  assert(effect._age == 0.0)
  effect.reset_effect()
  assert(effect._age == 0.0)
  assert(effect._dust.emitting)
  assert(effect.scale == Vector3.ONE)
  effect.queue_free()
  await process_frame
 var report := FileAccess.open("res://.godot/tornado_review/timings.json",FileAccess.WRITE)
 report.store_string(JSON.stringify(timings,"  "))
 report.close()
 print("TORNADO_GPU_TIMINGS: ",JSON.stringify(timings))
 stage.queue_free()
 await process_frame
 print("TORNADO_VFX_REVIEW_OK")
 quit()

func measure_gpu() -> Dictionary:
 for i in 20: await process_frame
 var gpu_times: Array[float] = []
 for i in 60:
  await process_frame
  gpu_times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 gpu_times.sort()
 return {"gpu_median_ms":gpu_times[30],"gpu_p95_ms":gpu_times[57],"frames":60,"resolution":"1280x800","steps":56}
