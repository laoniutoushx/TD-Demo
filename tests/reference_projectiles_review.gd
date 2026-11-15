extends SceneTree

var instances: Array = []
var output := "res://.godot/reference_review"
var lab: Node3D
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 root.size = Vector2i(1600, 900)
 DirAccess.make_dir_recursive_absolute(output)
 lab = Node3D.new()
 root.add_child(lab)
 var env := WorldEnvironment.new()
 env.environment = Environment.new()
 env.environment.background_mode = Environment.BG_COLOR
 env.environment.background_color = Color(0.07,0.075,0.085)
 env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 env.environment.ambient_light_color = Color(0.7,0.75,0.85)
 env.environment.ambient_light_energy = 0.6
 env.environment.glow_enabled = true
 env.environment.glow_intensity = 0.45
 env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 lab.add_child(env)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55,-30,0)
 lab.add_child(light)
 var plane := MeshInstance3D.new()
 var mesh := PlaneMesh.new()
 mesh.size = Vector2(40,40)
 plane.mesh = mesh
 var mat := StandardMaterial3D.new()
 mat.albedo_color = Color(0.15,0.16,0.18)
 mat.roughness = 0.9
 plane.material_override = mat
 lab.add_child(plane)
 var camera := Camera3D.new()
 camera.position = Vector3(3,5.5,10)
 camera.fov = 43
 lab.add_child(camera)
 camera.look_at(Vector3(0,1.2,0))
 camera.current = true
 var canvas := CanvasLayer.new()
 lab.add_child(canvas)
 var title := Label.new()
 title.position = Vector2(32,25)
 title.add_theme_font_size_override("font_size",26)
 title.text = "LATTICE                         PULSE                         CROWN"
 canvas.add_child(title)
 if "--benchmark" in OS.get_cmdline_user_args():
  await benchmark()
  lab.queue_free()
  await process_frame
  print("REFERENCE_BENCHMARK_OK")
  quit()
  return
 if "--sequence" in OS.get_cmdline_user_args():
  await sequence(camera)
  lab.queue_free()
  await process_frame
  print("REFERENCE_SEQUENCE_OK")
  quit()
  return
 var before := "--before" in OS.get_cmdline_user_args()
 for kind in ["running", "destory"]:
  for i in range(3):
   var code: String = ["lattice_orb","helix_orb","frost_orb"][i]
   var inst = load("res://VFX/projectiles/reference_set/vfx_%s_%s.tscn" % [code,kind]).instantiate()
   lab.add_child(inst)
   inst.position = Vector3((i-1)*3.2,1.3,0)
   inst.set_process(false)
   instances.append(inst)
  await create_timer(1.2).timeout
  for time in ([0.45,1.2] if kind == "running" else [0.035,0.12,0.3,0.55]):
   for inst in instances:
    if inst.has_method("seek_preview"):
     inst.seek_preview(time)
    else:
     inst.reset_effect()
     inst._process(time)
     inst.set_process(false)
   await process_frame
   await RenderingServer.frame_post_draw
   await process_frame
   await RenderingServer.frame_post_draw
   var path := output.path_join(("before" if before else "after") + "_%s_%03d.png" % [kind,roundi(time*1000)])
   if root.get_texture().get_image().save_png(path) != OK:
    push_error("CAPTURE_FAILED: " + path)
    quit(1)
    return
  if kind == "running" and not before:
   for view in ["side", "rts", "motion"]:
    camera.position = Vector3(2,4.0,10) if view == "side" else Vector3(0,10,7)
    camera.look_at(Vector3(0,1.2,0))
    for i in instances.size():
     var inst = instances[i]
     inst.rotation.y = -PI/2
     if view == "motion":
      inst.reset_effect()
      inst.set_process(false)
      for step in 60:
       var t := float(step)/60
       inst.position = Vector3((i-1)*3.2+t*1.4,1.3,sin(t*3)*0.3)
       inst.rotation.y = -PI/2+sin(t*2)*0.5
       inst._process(1.0/60)
     else:
      inst.seek_preview(0.45)
    await process_frame
    await RenderingServer.frame_post_draw
    await process_frame
    await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(output.path_join("after_"+view+".png"))
   camera.position = Vector3(3,5.5,10)
   camera.look_at(Vector3(0,1.2,0))
  for inst in instances: inst.queue_free()
  instances.clear()
  await process_frame
 lab.queue_free()
 await process_frame
 await create_timer(0.3).timeout
 print("REFERENCE_REVIEW_OK")
 quit()

func benchmark() -> void:
 root.size = Vector2i(1920,1080)
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps = 0
 var report := {"adapter":RenderingServer.get_video_adapter_name(), "viewport":"1920x1080", "warmup_seconds":3, "sample_seconds":5, "note":"Short isolated mixed-flight workload; not gameplay FPS or comparison against old prototype", "cases":[]}
 for count in [0,1,10,30]:
  var active: Array = []
  for i in count:
   var code: String = ["lattice_orb","helix_orb","frost_orb"][i%3]
   var inst = load("res://VFX/projectiles/reference_set/vfx_%s_running.tscn" % code).instantiate()
   lab.add_child(inst)
   inst.position = Vector3((i%6-2.5)*1.1,1.2,(i/6)*0.7-1.5)
   inst.rotation.y = -PI/2
   active.append(inst)
  await create_timer(3.0).timeout
  var samples: Array[float] = []
  var started := Time.get_ticks_usec()
  var previous := started
  while Time.get_ticks_usec()-started < 5000000:
   await process_frame
   var now := Time.get_ticks_usec()
   samples.append((now-previous)/1000.0)
   previous = now
  samples.sort()
  var result := {"instances":count,"frames":samples.size(),"p50_ms":samples[int(samples.size()*0.5)],"p95_ms":samples[int(samples.size()*0.95)],"p99_ms":samples[int(samples.size()*0.99)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)}
  report.cases.append(result)
  print(JSON.stringify(result))
  for inst in active: inst.queue_free()
  active.clear()
  await process_frame
 var file := FileAccess.open(output.path_join("benchmark.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))

func sequence(camera: Camera3D) -> void:
 root.size = Vector2i(1280,720)
 camera.position = Vector3(2,4,10)
 camera.look_at(Vector3(0,1.2,0))
 var flying: Array = []
 var hits: Array = []
 var folder := output.path_join("sequence")
 DirAccess.make_dir_recursive_absolute(folder)
 for i in range(3):
  var code: String = ["lattice_orb","helix_orb","frost_orb"][i]
  for kind in ["running","destory"]:
   var effect = load("res://VFX/projectiles/reference_set/vfx_%s_%s.tscn" % [code,kind]).instantiate()
   lab.add_child(effect)
   effect.position = Vector3((i-1)*3.2,1.3,0)
   effect.rotation.y = -PI/2
   effect.set_process(false)
   if kind == "running": flying.append(effect)
   else: hits.append(effect)
 await create_timer(1.2).timeout
 for frame in range(72):
  var time := float(frame)/24
  for i in range(3):
   flying[i].visible = time < 2
   hits[i].visible = time >= 2 and time < 2.7
   if time < 2: flying[i].seek_preview(time)
   elif time < 2.7: hits[i].seek_preview(time-2.0)
  await process_frame
  await RenderingServer.frame_post_draw
  await process_frame
  await RenderingServer.frame_post_draw
  var result := root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png" % frame))
  if result != OK: push_error("Sequence capture failed")
 for effect in flying+hits: effect.queue_free()
 await process_frame
