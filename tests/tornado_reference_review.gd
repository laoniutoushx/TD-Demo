extends SceneTree
var failures: int = 0
const CORE=preload("res://VFX/tornado/reference_set/reference_tornado.gd")
const STAGE=preload("res://tests/tornado_reference_stage.gd")
const OUTPUT="res://.godot/tornado_reference_review"
func _initialize() -> void:
 call_deferred("run")
func check(ok: bool,label: String) -> void:
 if not ok:
  failures+=1
  push_error("TORNADO_REFERENCE_FAILED: "+label)
func shot(path: String) -> void:
 await process_frame
 await RenderingServer.frame_post_draw
 check(root.get_texture().get_image().save_png(path)==OK,"Capture "+path)
func measure_gpu() -> Dictionary:
 for i in 8: await process_frame
 var samples: Array[float]=[]
 for i in 32:
  await process_frame
  samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
 samples.sort()
 return {"median_ms":samples[16],"p95_ms":samples[30],"samples":32}
func run() -> void:
 if DisplayServer.get_name()=="headless":
  push_error("Tornado reference review requires native rendering")
  quit(1)
  return
 root.size=Vector2i(1280,800)
 root.msaa_2d=Viewport.MSAA_DISABLED
 var stage=STAGE.new()
 stage.interactive=false
 root.add_child(stage)
 var factory=load("res://System/vfx_system/VFXSystem.gd").new()
 root.add_child(factory)
 await process_frame
 await create_timer(1.0).timeout
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 DirAccess.make_dir_recursive_absolute(OUTPUT)
 var report: Dictionary={"resolution":"1280x800","renderer":"Forward+","empty":await measure_gpu(),"entries":[]}
 for index in CORE.NAMES.size():
  var name: String=CORE.NAMES[index]
  var requested: String=""
  for argument in OS.get_cmdline_user_args():
   if argument.begins_with("--only="): requested=argument.trim_prefix("--only=")
  if not requested.is_empty() and name!=requested: continue
  var effect: Node3D=factory.create_vfx("tornado_"+name,"running")
  check(effect!=null,"Factory resolves "+name)
  if effect==null: continue
  stage.mount.add_child(effect)
  effect.set_process(false)
  stage.distance=maxf(10.0,effect._height*1.9)
  stage.update_camera()
  var normal_camera: Transform3D=stage.camera.transform
  effect.seek_preview(2.0)
  await create_timer(0.2).timeout
  var entry: Dictionary={"style":name,"gpu":await measure_gpu()}
  await shot(OUTPUT.path_join(name+".png"))
  effect.seek_preview(0.2)
  await shot(OUTPUT.path_join(name+"_forming.png"))
  effect.seek_preview(2.0)
  var stone_transform: Transform3D=effect._debris.multimesh.get_instance_transform(0)
  var puff_transform: Transform3D=effect._smoke.multimesh.get_instance_transform(0)
  effect.seek_preview(3.2)
  effect.seek_preview(2.0)
  check(effect._debris.multimesh.get_instance_transform(0).is_equal_approx(stone_transform),"Deterministic debris "+name)
  check(effect._smoke.multimesh.get_instance_transform(0).is_equal_approx(puff_transform),"Deterministic smoke "+name)
  stage.camera.projection=Camera3D.PROJECTION_ORTHOGONAL
  stage.camera.size=10.5
  stage.camera.position=Vector3(8,12,8)
  stage.camera.look_at(Vector3(0,2.8,0))
  await shot(OUTPUT.path_join(name+"_rts.png"))
  stage.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
  stage.camera.transform=normal_camera
  stage.environment.background_color=Color(0.65,0.7,0.75)
  await shot(OUTPUT.path_join(name+"_light.png"))
  stage.environment.background_color=Color(0.025,0.035,0.05)
  if "--capture" in OS.get_cmdline_user_args():
   var sequence: String=OUTPUT.path_join(name+"_sequence")
   DirAccess.make_dir_recursive_absolute(sequence)
   for frame in 48:
    effect.seek_preview(0.2+float(frame)/24.0)
    await shot(sequence.path_join("frame_%03d.png"%frame))
  var second: Node3D=factory.create_vfx("tornado_"+name,"running")
  stage.mount.add_child(second)
  second.set_process(false)
  check(second.mats[0]!=effect.mats[0],"Independent material "+name)
  second.seek_preview(1.1)
  check(not is_equal_approx(effect.age,second.age),"Independent clock "+name)
  effect.stop()
  check(not effect.visible and not effect.is_processing(),"Stop "+name)
  effect.play()
  check(effect.visible and effect.age==0.0,"Play resets "+name)
  effect.set_process(false)
  var old_id: int=effect.get_instance_id()
  factory.recycle_vfx(effect)
  var reused: Node3D=factory.create_vfx("tornado_"+name,"running")
  check(reused.get_instance_id()==old_id and reused.age==0.0,"Pool resets "+name)
  stage.mount.add_child(reused)
  reused.set_process(false)
  check(reused.transform==Transform3D.IDENTITY,"Root transform stable "+name)
  factory.recycle_vfx(reused)
  second.queue_free()
  await process_frame
  report.entries.append(entry)
  print("TORNADO_REFERENCE_STYLE_OK: ",name)
 check(report.entries.size()>0,"Requested style exists")
 factory.reset_session()
 factory.queue_free()
 stage.queue_free()
 await process_frame
 await process_frame
 var file:=FileAccess.open(OUTPUT.path_join("report.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))
 file.close()
 if failures==0: print("TORNADO_REFERENCE_OK")
 quit(1 if failures else 0)
