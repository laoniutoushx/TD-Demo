extends SceneTree
var failures := 0
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 if DisplayServer.get_name() == "headless":
  push_error("Catalog visual review requires native rendering")
  quit(1)
  return
 root.size = Vector2i(1280,800)
 var lab = load("res://VFX/lab/VFXLab.tscn").instantiate()
 root.add_child(lab)
 await process_frame
 var output := "res://.godot/vfx_lab/catalog"
 DirAccess.make_dir_recursive_absolute(output)
 var report := {"count":lab.EFFECTS.size(),"entries":[]}
 for i in lab.EFFECTS.size():
  lab.select_effect(i)
  lab.set_background(1 if lab.TAGS[i] == "贴花" else 0)
  lab.camera_preset(2 if lab.TAGS[i] == "贴花" else 0)
  var hold := 0.18 if lab.TAGS[i] in ["命中","建造"] else 0.45
  await create_timer(hold).timeout
  lab.frame_effect()
  await process_frame
  await RenderingServer.frame_post_draw
  var path := output.path_join("item_%02d.png" % i)
  var result: int = lab._view.get_texture().get_image().save_png(path)
  if result != OK:
   push_error("Catalog capture failed: "+path)
   failures += 1
  report.entries.append({"index":i,"label":lab.EFFECTS[i][0],"path":lab.EFFECTS[i][1],"category":lab.TAGS[i],"capture":path,"alive_at_capture":is_instance_valid(lab.effect)})
 var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(report,"  "))
 file.close()
 lab.stop()
 lab.queue_free()
 await process_frame
 await create_timer(0.3).timeout
 if failures == 0: print("VFX_CATALOG_REVIEW_OK")
 quit(1 if failures else 0)
